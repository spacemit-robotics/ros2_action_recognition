"""Launch action_recognition node with config."""
from launch import LaunchDescription
from launch_ros.substitutions import FindPackageShare
from launch_ros.actions import Node
from launch.substitutions import PathJoinSubstitution


def generate_launch_description():
    params_file = PathJoinSubstitution(
        [FindPackageShare("action_recognition"), "config", "action_recognition.yaml"]
    )
    return LaunchDescription(
        [
            Node(
                package="action_recognition",
                executable="action_recognition_node",
                name="action_recognition_node",
                output="screen",
                parameters=[params_file],
            )
        ]
    )
