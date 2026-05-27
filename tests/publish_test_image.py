#!/usr/bin/env python3
# Copyright (C) 2026 SpacemiT (Hangzhou) Technology Co. Ltd.
# SPDX-License-Identifier: Apache-2.0
"""Publish synthetic sensor_msgs/Image frames for perception topic tests."""

from __future__ import annotations

import argparse
import sys

import numpy as np
import rclpy
from rclpy.node import Node
from sensor_msgs.msg import Image


class TestImagePublisher(Node):
    def __init__(self, topic: str, count: int) -> None:
        super().__init__("test_image_publisher")
        self._publisher = self.create_publisher(Image, topic, 10)
        self._count = count
        self._published = 0
        self._done = False
        self._timer = self.create_timer(0.1, self._publish_image)

    @property
    def done(self) -> bool:
        return self._done

    def _publish_image(self) -> None:
        if self._done:
            return
        if self._published >= self._count:
            self.get_logger().info(f"Published {self._published} images, done")
            self._timer.cancel()
            self._done = True
            return

        msg = Image()
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.header.frame_id = "camera"
        msg.height = 480
        msg.width = 640
        msg.encoding = "bgr8"
        msg.step = 640 * 3
        msg.data = np.random.randint(0, 255, (480, 640, 3), dtype=np.uint8).tobytes()
        self._publisher.publish(msg)
        self._published += 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--topic", default="/camera/image_raw")
    parser.add_argument("--count", type=int, default=10)
    args = parser.parse_args()

    rclpy.init()
    node = TestImagePublisher(args.topic, args.count)
    try:
        while rclpy.ok() and not node.done:
            rclpy.spin_once(node, timeout_sec=0.1)
    finally:
        if rclpy.ok():
            node.destroy_node()
            rclpy.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
