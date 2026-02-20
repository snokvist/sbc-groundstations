/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef ROCKNIX_INPUT_POLLDEV_COMPAT_H
#define ROCKNIX_INPUT_POLLDEV_COMPAT_H

#if defined(__has_include)
#if __has_include(<linux/input-polldev.h>)
#include <linux/input-polldev.h>
#define ROCKNIX_HAVE_INPUT_POLLDEV 1
#endif
#endif

#ifndef ROCKNIX_HAVE_INPUT_POLLDEV
#include <linux/device.h>
#include <linux/input.h>
#include <linux/jiffies.h>
#include <linux/slab.h>
#include <linux/workqueue.h>

struct input_polled_dev {
	struct input_dev *input;
	void *private;
	void (*poll)(struct input_polled_dev *dev);
	void (*open)(struct input_polled_dev *dev);
	void (*close)(struct input_polled_dev *dev);
	unsigned int poll_interval;
	struct delayed_work work;
	bool started;
};

static inline unsigned long rocknix_poll_delay_jiffies(unsigned int interval_ms)
{
	if (!interval_ms)
		interval_ms = 1;

	return msecs_to_jiffies(interval_ms);
}

static inline void rocknix_input_polled_workfn(struct work_struct *work)
{
	struct input_polled_dev *poll_dev =
		container_of(to_delayed_work(work), struct input_polled_dev, work);

	if (!poll_dev->started)
		return;

	if (poll_dev->poll)
		poll_dev->poll(poll_dev);

	schedule_delayed_work(&poll_dev->work,
			      rocknix_poll_delay_jiffies(poll_dev->poll_interval));
}

static inline int rocknix_input_polled_open(struct input_dev *input)
{
	struct input_polled_dev *poll_dev = input_get_drvdata(input);

	if (!poll_dev)
		return -EINVAL;

	poll_dev->started = true;

	if (poll_dev->open)
		poll_dev->open(poll_dev);

	schedule_delayed_work(&poll_dev->work,
			      rocknix_poll_delay_jiffies(poll_dev->poll_interval));

	return 0;
}

static inline void rocknix_input_polled_close(struct input_dev *input)
{
	struct input_polled_dev *poll_dev = input_get_drvdata(input);

	if (!poll_dev)
		return;

	poll_dev->started = false;
	cancel_delayed_work_sync(&poll_dev->work);

	if (poll_dev->close)
		poll_dev->close(poll_dev);
}

static inline struct input_polled_dev *
devm_input_allocate_polled_device(struct device *dev)
{
	struct input_polled_dev *poll_dev;
	struct input_dev *input;

	poll_dev = devm_kzalloc(dev, sizeof(*poll_dev), GFP_KERNEL);
	if (!poll_dev)
		return NULL;

	input = devm_input_allocate_device(dev);
	if (!input)
		return NULL;

	poll_dev->input = input;
	INIT_DELAYED_WORK(&poll_dev->work, rocknix_input_polled_workfn);

	return poll_dev;
}

static inline int input_register_polled_device(struct input_polled_dev *poll_dev)
{
	if (!poll_dev || !poll_dev->input)
		return -EINVAL;

	input_set_drvdata(poll_dev->input, poll_dev);
	poll_dev->input->open = rocknix_input_polled_open;
	poll_dev->input->close = rocknix_input_polled_close;

	return input_register_device(poll_dev->input);
}
#endif

#endif
