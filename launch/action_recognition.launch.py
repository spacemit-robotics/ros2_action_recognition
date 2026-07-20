"""Launch action_recognition node with config."""
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch_ros.substitutions import FindPackageShare
from launch_ros.actions import Node
from launch.substitutions import LaunchConfiguration, PathJoinSubstitution


def generate_launch_description():
    params_file = PathJoinSubstitution(
        [FindPackageShare("action_recognition"), "config", "action_recognition.yaml"]
    )
    return LaunchDescription(
        [
            DeclareLaunchArgument("sequence_length", default_value="30"),
            Node(
                package="action_recognition",
                executable="action_recognition_node",
                name="action_recognition_node",
                output="screen",
                parameters=[
                    params_file,
                    {
                        "sequence_length": LaunchConfiguration("sequence_length"),
                    },
                ],
            )
        ]
    )
