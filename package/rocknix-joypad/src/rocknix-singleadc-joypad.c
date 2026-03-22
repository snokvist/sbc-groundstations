/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * ROCKNIX singleadc joypad driver
 *
 * Copyright (C) 2024 ROCKNIX (https://github.com/ROCKNIX)
 *
 * Trimmed version: removed Miyoo serial joypad support (not needed for
 * RK3566 devices like the RGB20Pro which use SARADC + analog mux).
 */

#include <linux/module.h>
#include <linux/input-polldev.h>
#include <linux/platform_device.h>
#include <linux/iio/consumer.h>
#include <linux/version.h>
#if (LINUX_VERSION_CODE < KERNEL_VERSION(6, 3, 0))
#include <linux/of_gpio.h>
#else
#include <linux/of_gpio_legacy.h>
#endif
#include <linux/delay.h>
#include <linux/pwm.h>
#include "rocknix-joypad.h"

#define DRV_NAME "rocknix-singleadc-joypad"

#define	ADC_MAX_VOLTAGE		1800
#define	ADC_DATA_TUNING(x, p)	((x * p) / 100)
#define	ADC_TUNING_DEFAULT	180
#define	CLAMP(x, low, high)  (((x) > (high)) ? (high) : (((x) < (low)) ? (low) : (x)))

struct bt_adc {
	int value;
	int report_type;
	int max, min;
	int cal;
	int scale;
	bool invert;
	int amux_ch;
	int tuning_p, tuning_n;
};

struct analog_mux {
	struct iio_channel *iio_ch;
	int sel_a_gpio, sel_b_gpio;
	int en_gpio;
};

struct bt_gpio {
	const char *label;
	int num;
	int report_type;
	int linux_code;
	bool old_value;
	bool active_level;
};

struct joypad {
	struct device *dev;
	int poll_interval;

	bool enable;

	struct analog_mux *amux;
	int amux_count;
	struct bt_adc *adcs;

	bool invert_absx;
	bool invert_absy;
	bool invert_absrx;
	bool invert_absry;

	int bt_gpio_count;
	struct bt_gpio *gpios;

	int auto_repeat;

	int bt_adc_fuzz, bt_adc_flat;
	int bt_adc_scale;
	int bt_adc_deadzone;

	struct mutex lock;

	struct input_dev *input;
	struct pwm_device *pwm;
	struct work_struct play_work;
	u16 level;
	u16 boost_weak;
	u16 boost_strong;
	bool has_rumble;
	bool rumble_enabled;
};

extern struct input_dev *joypad_input_g;

static int pwm_vibrator_start(struct joypad *joypad)
{
	struct pwm_state state;
	int err;

	pwm_get_state(joypad->pwm, &state);
	pwm_set_relative_duty_cycle(&state, joypad->level, 0xffff);
	state.enabled = true;

#if (LINUX_VERSION_CODE < KERNEL_VERSION(6, 11, 0))
	err = pwm_apply_state(joypad->pwm, &state);
#else
	err = pwm_apply_might_sleep(joypad->pwm, &state);
#endif
	if (err) {
		dev_err(joypad->dev, "failed to apply pwm state: %d", err);
		return err;
	}

	return 0;
}

static void pwm_vibrator_stop(struct joypad *joypad)
{
	pwm_disable(joypad->pwm);
}

static void pwm_vibrator_play_work(struct work_struct *work)
{
	struct joypad *joypad = container_of(work, struct joypad, play_work);

	mutex_lock(&joypad->lock);
	if (!joypad->rumble_enabled) {
		pwm_vibrator_stop(joypad);
		mutex_unlock(&joypad->lock);
		return;
	}

	if (joypad->level)
		pwm_vibrator_start(joypad);
	else
		pwm_vibrator_stop(joypad);

	mutex_unlock(&joypad->lock);
}

static int joypad_amux_select(struct analog_mux *amux, int channel)
{
	gpio_set_value_cansleep(amux->en_gpio, 0);

	switch (channel) {
	case 0:	/* ABS_RY */
		gpio_set_value_cansleep(amux->sel_a_gpio, 0);
		gpio_set_value_cansleep(amux->sel_b_gpio, 0);
		break;
	case 1:	/* ABS_RX */
		gpio_set_value_cansleep(amux->sel_a_gpio, 0);
		gpio_set_value_cansleep(amux->sel_b_gpio, 1);
		break;
	case 2:	/* ABS_Y */
		gpio_set_value_cansleep(amux->sel_a_gpio, 1);
		gpio_set_value_cansleep(amux->sel_b_gpio, 0);
		break;
	case 3:	/* ABS_X */
		gpio_set_value_cansleep(amux->sel_a_gpio, 1);
		gpio_set_value_cansleep(amux->sel_b_gpio, 1);
		break;
	default:
		gpio_set_value_cansleep(amux->en_gpio, 1);
		return -1;
	}
	/* mux switching speed : 35ns(on) / 9ns(off) */
	usleep_range(10, 20);
	return 0;
}

static int joypad_adc_read(struct analog_mux *amux, struct bt_adc *adc)
{
	int value;

	if (joypad_amux_select(amux, adc->amux_ch))
		return 0;

	iio_read_channel_raw(amux->iio_ch, &value);

	value *= adc->scale;

	return value;
}

/* sysfs: /sys/devices/platform/rocknix-singleadc-joypad/rumble_enable */
static ssize_t joypad_store_rumble_enable(struct device *dev,
					  struct device_attribute *attr,
					  const char *buf, size_t count)
{
	struct platform_device *pdev = to_platform_device(dev);
	struct joypad *joypad = platform_get_drvdata(pdev);
	bool enable = simple_strtoul(buf, NULL, 10);

	mutex_lock(&joypad->lock);
	if (enable && !joypad->rumble_enabled) {
		joypad->rumble_enabled = true;
	} else if (!enable && joypad->rumble_enabled) {
		joypad->rumble_enabled = false;
		joypad->level = 0;
		cancel_work_sync(&joypad->play_work);
		pwm_vibrator_stop(joypad);
	}
	mutex_unlock(&joypad->lock);
	return count;
}

static ssize_t joypad_show_rumble_enable(struct device *dev,
					 struct device_attribute *attr,
					 char *buf)
{
	struct platform_device *pdev = to_platform_device(dev);
	struct joypad *joypad = platform_get_drvdata(pdev);
	return sprintf(buf, "%d\n", joypad->rumble_enabled ? 1 : 0);
}

static DEVICE_ATTR(rumble_enable, S_IWUSR | S_IRUGO,
		   joypad_show_rumble_enable,
		   joypad_store_rumble_enable);

static struct attribute *joypad_rumble_attrs[] = {
	&dev_attr_rumble_enable.attr,
	NULL,
};

static struct attribute_group joypad_rumble_attr_group = {
	.attrs = joypad_rumble_attrs,
};

static void joypad_gpio_check(struct input_polled_dev *poll_dev)
{
	struct joypad *joypad = poll_dev->private;
	int nbtn, value;

	for (nbtn = 0; nbtn < joypad->bt_gpio_count; nbtn++) {
		struct bt_gpio *gpio = &joypad->gpios[nbtn];

		if (gpio_get_value_cansleep(gpio->num) < 0) {
			dev_err(joypad->dev, "failed to get gpio state\n");
			continue;
		}
		value = gpio_get_value_cansleep(gpio->num);
		if (value != gpio->old_value) {
			input_event(poll_dev->input,
				gpio->report_type,
				gpio->linux_code,
				(value == gpio->active_level) ? 1 : 0);
			gpio->old_value = value;
		}
	}
	input_sync(poll_dev->input);
}

static void joypad_adc_check(struct input_polled_dev *poll_dev)
{
	struct joypad *joypad = poll_dev->private;
	int nbtn;
	int mag;

	/* Assumes even number of axes, paired sequentially (X then Y) */
	for (nbtn = 0; nbtn < joypad->amux_count; nbtn += 2) {
		struct bt_adc *adcx = &joypad->adcs[nbtn];
		struct bt_adc *adcy = &joypad->adcs[nbtn + 1];

		adcx->value = joypad_adc_read(joypad->amux, adcx);
		if (!adcx->value)
			continue;
		adcx->value = adcx->value - adcx->cal;

		adcy->value = joypad_adc_read(joypad->amux, adcy);
		if (!adcy->value)
			continue;
		adcy->value = adcy->value - adcy->cal;

		/* Scaled Radial Deadzone */
		mag = int_sqrt((adcx->value * adcx->value) + (adcy->value * adcy->value));
		if (joypad->bt_adc_deadzone) {
			if (mag <= joypad->bt_adc_deadzone) {
				adcx->value = 0;
				adcy->value = 0;
			} else {
				adcx->value = (((adcx->max * adcx->value) / mag) * (mag - joypad->bt_adc_deadzone)) / (adcx->max - joypad->bt_adc_deadzone);
				adcy->value = (((adcy->max * adcy->value) / mag) * (mag - joypad->bt_adc_deadzone)) / (adcy->max - joypad->bt_adc_deadzone);
			}
		}

		/* adc data tuning */
		if (adcx->tuning_n && adcx->value < 0)
			adcx->value = ADC_DATA_TUNING(adcx->value, adcx->tuning_n);
		if (adcx->tuning_p && adcx->value > 0)
			adcx->value = ADC_DATA_TUNING(adcx->value, adcx->tuning_p);
		if (adcy->tuning_n && adcy->value < 0)
			adcy->value = ADC_DATA_TUNING(adcy->value, adcy->tuning_n);
		if (adcy->tuning_p && adcy->value > 0)
			adcy->value = ADC_DATA_TUNING(adcy->value, adcy->tuning_p);

		/* Clamp */
		adcx->value = adcx->value > adcx->max ? adcx->max : adcx->value;
		adcx->value = adcx->value < adcx->min ? adcx->min : adcx->value;
		adcy->value = adcy->value > adcy->max ? adcy->max : adcy->value;
		adcy->value = adcy->value < adcy->min ? adcy->min : adcy->value;

		input_report_abs(poll_dev->input, adcx->report_type,
			adcx->invert ? adcx->value * (-1) : adcx->value);
		input_report_abs(poll_dev->input, adcy->report_type,
			adcy->invert ? adcy->value * (-1) : adcy->value);
	}
	input_sync(poll_dev->input);
}

static void joypad_poll(struct input_polled_dev *poll_dev)
{
	struct joypad *joypad = poll_dev->private;

	if (joypad->enable) {
		joypad_adc_check(poll_dev);
		joypad_gpio_check(poll_dev);
	}
	if (poll_dev->poll_interval != joypad->poll_interval) {
		mutex_lock(&joypad->lock);
		poll_dev->poll_interval = joypad->poll_interval;
		mutex_unlock(&joypad->lock);
	}
}

static void joypad_open(struct input_polled_dev *poll_dev)
{
	struct joypad *joypad = poll_dev->private;
	int nbtn;

	for (nbtn = 0; nbtn < joypad->bt_gpio_count; nbtn++) {
		struct bt_gpio *gpio = &joypad->gpios[nbtn];
		int val = gpio_get_value_cansleep(gpio->num);
		if (val < 0)
			val = gpio->active_level ? 0 : 1;
		gpio->old_value = val;

		input_event(poll_dev->input, gpio->report_type,
				gpio->linux_code,
				(val == gpio->active_level) ? 1 : 0);
	}
	input_sync(poll_dev->input);

	for (nbtn = 0; nbtn < joypad->amux_count; nbtn++) {
		struct bt_adc *adc = &joypad->adcs[nbtn];

		adc->value = joypad_adc_read(joypad->amux, adc);
		if (!adc->value) {
			dev_err(joypad->dev, "%s : saradc channels[%d]!\n",
				__func__, nbtn);
			continue;
		}
		adc->cal = adc->value;
	}
	joypad_adc_check(poll_dev);
	joypad_gpio_check(poll_dev);

	mutex_lock(&joypad->lock);
	joypad->enable = true;
	mutex_unlock(&joypad->lock);
}

static void joypad_close(struct input_polled_dev *poll_dev)
{
	struct joypad *joypad = poll_dev->private;

	if (joypad->has_rumble) {
		cancel_work_sync(&joypad->play_work);
		pwm_vibrator_stop(joypad);
	}

	mutex_lock(&joypad->lock);
	joypad->enable = false;
	mutex_unlock(&joypad->lock);
}

static int joypad_amux_setup(struct device *dev, struct joypad *joypad)
{
	struct analog_mux *amux;
	enum iio_chan_type type;
	enum of_gpio_flags flags;
	int ret;

	joypad->amux = devm_kzalloc(dev, sizeof(struct analog_mux), GFP_KERNEL);
	if (!joypad->amux) {
		dev_err(dev, "%s amux devm_kzmalloc error!", __func__);
		return -ENOMEM;
	}
	amux = joypad->amux;
	amux->iio_ch = devm_iio_channel_get(dev, "amux_adc");
	if (PTR_ERR(amux->iio_ch) == -EPROBE_DEFER)
		return -EPROBE_DEFER;
	if (IS_ERR(amux->iio_ch)) {
		dev_err(dev, "iio channel get error\n");
		return -EINVAL;
	}
	if (!amux->iio_ch->indio_dev)
		return -ENXIO;

	if (iio_get_channel_type(amux->iio_ch, &type))
		return -EINVAL;

	if (type != IIO_VOLTAGE) {
		dev_err(dev, "Incompatible channel type %d\n", type);
		return -EINVAL;
	}

	amux->sel_a_gpio = of_get_named_gpio_flags(dev->of_node,
				"amux-a-gpios", 0, &flags);
	if (gpio_is_valid(amux->sel_a_gpio)) {
		ret = devm_gpio_request_one(dev, amux->sel_a_gpio, GPIOF_IN, "amux-sel-a");
		if (ret < 0) {
			dev_err(dev, "%s : failed to request amux-sel-a %d\n",
				__func__, amux->sel_a_gpio);
			goto err_out;
		}
		ret = gpio_direction_output(amux->sel_a_gpio, 0);
		if (ret < 0)
			goto err_out;
	}

	amux->sel_b_gpio = of_get_named_gpio_flags(dev->of_node,
				"amux-b-gpios", 0, &flags);
	if (gpio_is_valid(amux->sel_b_gpio)) {
		ret = devm_gpio_request_one(dev, amux->sel_b_gpio, GPIOF_IN, "amux-sel-b");
		if (ret < 0) {
			dev_err(dev, "%s : failed to request amux-sel-b %d\n",
				__func__, amux->sel_b_gpio);
			goto err_out;
		}
		ret = gpio_direction_output(amux->sel_b_gpio, 0);
		if (ret < 0)
			goto err_out;
	}

	amux->en_gpio = of_get_named_gpio_flags(dev->of_node,
				"amux-en-gpios", 0, &flags);
	if (gpio_is_valid(amux->en_gpio)) {
		ret = devm_gpio_request_one(dev, amux->en_gpio, GPIOF_IN, "amux-en");
		if (ret < 0) {
			dev_err(dev, "%s : failed to request amux-en %d\n",
				__func__, amux->en_gpio);
			goto err_out;
		}
		ret = gpio_direction_output(amux->en_gpio, 0);
		if (ret < 0)
			goto err_out;
	}
	return 0;
err_out:
	return ret;
}

static int joypad_adc_setup(struct device *dev, struct joypad *joypad)
{
	int nbtn;
	u32 channel_mapping[] = {0, 1, 2, 3};

	if (device_property_present(dev, "amux-channel-mapping")) {
		int ret;
		ret = of_property_read_u32_array(dev->of_node,
				"amux-channel-mapping", channel_mapping, 4);
		if (ret < 0) {
			dev_err(dev, "invalid channel mapping\n");
			return -EINVAL;
		}
	}

	joypad->adcs = devm_kzalloc(dev, joypad->amux_count *
				sizeof(struct bt_adc), GFP_KERNEL);
	if (!joypad->adcs) {
		dev_err(dev, "%s devm_kzmalloc error!", __func__);
		return -ENOMEM;
	}

	for (nbtn = 0; nbtn < joypad->amux_count; nbtn++) {
		struct bt_adc *adc = &joypad->adcs[nbtn];

		adc->scale = joypad->bt_adc_scale;

		adc->max = (ADC_MAX_VOLTAGE / 2);
		adc->min = (ADC_MAX_VOLTAGE / 2) * (-1);
		if (adc->scale) {
			adc->max *= adc->scale;
			adc->min *= adc->scale;
		}
		adc->invert = false;

		switch (nbtn) {
		case 0:
			if (joypad->invert_absry)
				adc->invert = true;
			adc->report_type = ABS_RY;
			if (device_property_read_u32(dev, "abs_ry-p-tuning", &adc->tuning_p))
				adc->tuning_p = ADC_TUNING_DEFAULT;
			if (device_property_read_u32(dev, "abs_ry-n-tuning", &adc->tuning_n))
				adc->tuning_n = ADC_TUNING_DEFAULT;
			break;
		case 1:
			if (joypad->invert_absrx)
				adc->invert = true;
			adc->report_type = ABS_RX;
			if (device_property_read_u32(dev, "abs_rx-p-tuning", &adc->tuning_p))
				adc->tuning_p = ADC_TUNING_DEFAULT;
			if (device_property_read_u32(dev, "abs_rx-n-tuning", &adc->tuning_n))
				adc->tuning_n = ADC_TUNING_DEFAULT;
			break;
		case 2:
			if (joypad->invert_absy)
				adc->invert = true;
			adc->report_type = ABS_Y;
			if (device_property_read_u32(dev, "abs_y-p-tuning", &adc->tuning_p))
				adc->tuning_p = ADC_TUNING_DEFAULT;
			if (device_property_read_u32(dev, "abs_y-n-tuning", &adc->tuning_n))
				adc->tuning_n = ADC_TUNING_DEFAULT;
			break;
		case 3:
			if (joypad->invert_absx)
				adc->invert = true;
			adc->report_type = ABS_X;
			if (device_property_read_u32(dev, "abs_x-p-tuning", &adc->tuning_p))
				adc->tuning_p = ADC_TUNING_DEFAULT;
			if (device_property_read_u32(dev, "abs_x-n-tuning", &adc->tuning_n))
				adc->tuning_n = ADC_TUNING_DEFAULT;
			break;
		default:
			dev_err(dev, "%s amux count(%d) error!", __func__, nbtn);
			return -EINVAL;
		}
		adc->amux_ch = channel_mapping[nbtn];
	}
	return 0;
}

static int joypad_gpio_setup(struct device *dev, struct joypad *joypad)
{
	struct device_node *node, *pp;
	int nbtn;

	node = dev->of_node;
	if (!node)
		return -ENODEV;

	joypad->gpios = devm_kzalloc(dev, joypad->bt_gpio_count *
				sizeof(struct bt_gpio), GFP_KERNEL);

	if (!joypad->gpios) {
		dev_err(dev, "%s devm_kzmalloc error!", __func__);
		return -ENOMEM;
	}

	nbtn = 0;
	for_each_child_of_node(node, pp) {
		enum of_gpio_flags flags;
		struct bt_gpio *gpio = &joypad->gpios[nbtn++];
		int error;

		gpio->num = of_get_gpio_flags(pp, 0, &flags);
		if (gpio->num < 0) {
			error = gpio->num;
			dev_err(dev, "Failed to get gpio flags, error: %d\n", error);
			return error;
		}

		gpio->active_level = (flags & OF_GPIO_ACTIVE_LOW) ? 0 : 1;
		gpio->label = of_get_property(pp, "label", NULL);

		if (gpio_is_valid(gpio->num)) {
			error = devm_gpio_request_one(dev, gpio->num,
						      GPIOF_IN, gpio->label);
			if (error < 0) {
				dev_err(dev, "Failed to request GPIO %d, error %d\n",
					gpio->num, error);
				return error;
			}
		}
		if (of_property_read_u32(pp, "linux,code", &gpio->linux_code)) {
			dev_err(dev, "Button without keycode: 0x%x\n", gpio->num);
			return -EINVAL;
		}
		if (of_property_read_u32(pp, "linux,input-type", &gpio->report_type))
			gpio->report_type = EV_KEY;
	}
	if (nbtn == 0)
		return -EINVAL;

	return 0;
}

static int rumble_play_effect(struct input_dev *dev, void *data, struct ff_effect *effect)
{
	struct joypad *joypad = data;
	u32 boosted_level;

	if (effect->type != FF_RUMBLE)
		return 0;

	mutex_lock(&joypad->lock);
	if (!joypad->rumble_enabled) {
		mutex_unlock(&joypad->lock);
		return 0;
	}

	if (effect->u.rumble.strong_magnitude)
		boosted_level = effect->u.rumble.strong_magnitude + joypad->boost_strong;
	else
		boosted_level = effect->u.rumble.weak_magnitude + joypad->boost_weak;

	joypad->level = (u16)CLAMP(boosted_level, 0, 0xffff);

	mutex_unlock(&joypad->lock);

	schedule_work(&joypad->play_work);
	return 0;
}

static int joypad_rumble_setup(struct device *dev, struct joypad *joypad)
{
	int error;
	struct pwm_state state;

	joypad->pwm = devm_pwm_get(dev, "enable");
	if (IS_ERR(joypad->pwm)) {
		dev_err(dev, "rumble get error\n");
		return -EINVAL;
	}

	INIT_WORK(&joypad->play_work, pwm_vibrator_play_work);

	pwm_init_state(joypad->pwm, &state);
	state.enabled = false;

#if (LINUX_VERSION_CODE < KERNEL_VERSION(6, 11, 0))
	error = pwm_apply_state(joypad->pwm, &state);
#else
	error = pwm_apply_might_sleep(joypad->pwm, &state);
#endif
	if (error) {
		dev_err(dev, "failed to apply initial PWM state: %d", error);
		return error;
	}

	dev_info(dev, "rumble setup success!\n");
	return 0;
}

static int joypad_input_setup(struct device *dev, struct joypad *joypad)
{
	struct input_polled_dev *poll_dev;
	struct input_dev *input;
	int nbtn, error;
	u32 joypad_bustype = BUS_HOST;
	u32 joypad_vendor = 0;
	u32 joypad_revision = 0;
	u32 joypad_product = 0;

	poll_dev = devm_input_allocate_polled_device(dev);
	if (!poll_dev) {
		dev_err(dev, "no memory for polled device\n");
		return -ENOMEM;
	}

	poll_dev->private	= joypad;
	poll_dev->poll		= joypad_poll;
	poll_dev->poll_interval	= joypad->poll_interval;
	poll_dev->open		= joypad_open;
	poll_dev->close		= joypad_close;

	input = poll_dev->input;

	input->name = DRV_NAME;

	joypad_input_g = input;

	device_property_read_string(dev, "joypad-name", &input->name);
	input->phys = DRV_NAME "/input0";

	device_property_read_u32(dev, "joypad-bustype", &joypad_bustype);
	device_property_read_u32(dev, "joypad-vendor", &joypad_vendor);
	device_property_read_u32(dev, "joypad-revision", &joypad_revision);
	device_property_read_u32(dev, "joypad-product", &joypad_product);
	input->id.bustype = (u16)joypad_bustype;
	input->id.vendor  = (u16)joypad_vendor;
	input->id.product = (u16)joypad_product;
	input->id.version = (u16)joypad_revision;

	if (joypad->amux_count > 0) {
		__set_bit(EV_ABS, input->evbit);
	}

	for (nbtn = 0; nbtn < joypad->amux_count; nbtn++) {
		struct bt_adc *adc = &joypad->adcs[nbtn];
		input_set_abs_params(input, adc->report_type,
				adc->min, adc->max,
				joypad->bt_adc_fuzz,
				joypad->bt_adc_flat);
		dev_info(dev,
			"%s : SCALE = %d, ABS min = %d, max = %d,"
			" fuzz = %d, flat = %d, deadzone = %d\n",
			__func__, adc->scale, adc->min, adc->max,
			joypad->bt_adc_fuzz, joypad->bt_adc_flat,
			joypad->bt_adc_deadzone);
	}

	/* Rumble setup */
	if (joypad->has_rumble) {
		u32 boost_weak = 0;
		u32 boost_strong = 0;
		device_property_read_u32(dev, "rumble-boost-weak", &boost_weak);
		device_property_read_u32(dev, "rumble-boost-strong", &boost_strong);
		joypad->boost_weak = boost_weak;
		joypad->boost_strong = boost_strong;
		input_set_capability(input, EV_FF, FF_RUMBLE);
		error = input_ff_create_memless(input, joypad, rumble_play_effect);
		if (error) {
			dev_err(dev, "unable to register rumble, err=%d\n", error);
			return error;
		}
	}

	/* GPIO key setup */
	__set_bit(EV_KEY, input->evbit);
	for (nbtn = 0; nbtn < joypad->bt_gpio_count; nbtn++) {
		struct bt_gpio *gpio = &joypad->gpios[nbtn];
		input_set_capability(input, gpio->report_type, gpio->linux_code);
	}

	if (joypad->auto_repeat)
		__set_bit(EV_REP, input->evbit);

	joypad->dev = dev;

	error = input_register_polled_device(poll_dev);
	if (error) {
		dev_err(dev, "unable to register polled device, err=%d\n", error);
		return error;
	}

	return 0;
}

static int joypad_dt_parse(struct device *dev, struct joypad *joypad)
{
	int error = 0;

	device_property_read_u32(dev, "button-adc-fuzz", &joypad->bt_adc_fuzz);
	device_property_read_u32(dev, "button-adc-flat", &joypad->bt_adc_flat);
	device_property_read_u32(dev, "button-adc-scale", &joypad->bt_adc_scale);
	device_property_read_u32(dev, "button-adc-deadzone", &joypad->bt_adc_deadzone);

	device_property_read_u32(dev, "amux-count", &joypad->amux_count);
	device_property_read_u32(dev, "poll-interval", &joypad->poll_interval);

	joypad->auto_repeat = device_property_present(dev, "autorepeat");

	joypad->invert_absx = device_property_present(dev, "invert-absx");
	joypad->invert_absy = device_property_present(dev, "invert-absy");
	joypad->invert_absrx = device_property_present(dev, "invert-absrx");
	joypad->invert_absry = device_property_present(dev, "invert-absry");
	dev_info(dev, "%s : invert-absx=%d, invert-absy=%d, invert-absrx=%d, invert-absry=%d\n",
		__func__, joypad->invert_absx, joypad->invert_absy,
		joypad->invert_absrx, joypad->invert_absry);

	joypad->bt_gpio_count = device_get_child_node_count(dev);

	if ((joypad->amux_count == 0) && (joypad->bt_gpio_count == 0)) {
		dev_err(dev, "adc key = %d, gpio key = %d error!",
			joypad->amux_count, joypad->bt_gpio_count);
	}

	if (joypad->amux_count > 0) {
		error = joypad_adc_setup(dev, joypad);
		if (error)
			return error;

		error = joypad_amux_setup(dev, joypad);
		if (error)
			return error;
	}

	error = joypad_gpio_setup(dev, joypad);
	if (error)
		return error;

	dev_info(dev, "%s : adc key cnt = %d, gpio key cnt = %d\n",
			__func__, joypad->amux_count, joypad->bt_gpio_count);

	joypad->has_rumble = device_property_present(dev, "pwm-names");
	if (joypad->has_rumble)
		dev_info(dev, "%s : has rumble\n", __func__);

	return error;
}

static int __maybe_unused joypad_suspend(struct device *dev)
{
	struct platform_device *pdev = to_platform_device(dev);
	struct joypad *joypad = platform_get_drvdata(pdev);
	if (joypad->has_rumble) {
		cancel_work_sync(&joypad->play_work);
		if (joypad->level)
			pwm_vibrator_stop(joypad);
	}
	return 0;
}

static int __maybe_unused joypad_resume(struct device *dev)
{
	struct platform_device *pdev = to_platform_device(dev);
	struct joypad *joypad = platform_get_drvdata(pdev);
	if (joypad->has_rumble) {
		if (joypad->level)
			pwm_vibrator_start(joypad);
	}
	return 0;
}

static SIMPLE_DEV_PM_OPS(joypad_pm_ops, joypad_suspend, joypad_resume);

static int joypad_probe(struct platform_device *pdev)
{
	struct joypad *joypad;
	struct device *dev = &pdev->dev;
	int error;

	joypad = devm_kzalloc(dev, sizeof(struct joypad), GFP_KERNEL);
	if (!joypad) {
		dev_err(dev, "joypad devm_kzmalloc error!");
		return -ENOMEM;
	}

	error = joypad_dt_parse(dev, joypad);
	if (error) {
		dev_err(dev, "dt parse error!(err = %d)\n", error);
		return error;
	}

	mutex_init(&joypad->lock);
	platform_set_drvdata(pdev, joypad);

	error = joypad_input_setup(dev, joypad);
	if (error) {
		dev_err(dev, "input setup failed!(err = %d)\n", error);
		return error;
	}

	if (joypad->has_rumble) {
		error = sysfs_create_group(&pdev->dev.kobj, &joypad_rumble_attr_group);
		if (error) {
			dev_err(dev, "create sysfs group fail, error: %d\n", error);
			return error;
		}

		error = joypad_rumble_setup(dev, joypad);
		if (error) {
			dev_err(dev, "rumble setup failed!(err = %d)\n", error);
			return error;
		}

		joypad->rumble_enabled = true;
	}

	dev_info(dev, "%s : probe success\n", __func__);
	return 0;
}

static const struct of_device_id joypad_of_match[] = {
	{ .compatible = "rocknix-singleadc-joypad", },
	{},
};

MODULE_DEVICE_TABLE(of, joypad_of_match);

static struct platform_driver joypad_driver = {
	.probe = joypad_probe,
	.driver = {
		.name = DRV_NAME,
		.pm = &joypad_pm_ops,
		.of_match_table = of_match_ptr(joypad_of_match),
	},
};

static int __init joypad_init(void)
{
	return platform_driver_register(&joypad_driver);
}

static void __exit joypad_exit(void)
{
	platform_driver_unregister(&joypad_driver);
}

late_initcall(joypad_init);
module_exit(joypad_exit);

MODULE_AUTHOR("ROCKNIX");
MODULE_DESCRIPTION("ROCKNIX singleadc joypad driver");
MODULE_LICENSE("GPL");
MODULE_ALIAS("platform:" DRV_NAME);
MODULE_INFO(intree, "Y");
