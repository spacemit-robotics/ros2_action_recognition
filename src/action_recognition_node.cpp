/**
 * @file action_recognition_node.cpp
 * @brief ROS2 action recognition: subscribe BodyPoseArray, run STGCN on 30-frame
 *        skeleton sequences, publish ActionArray.
 *
 * Copyright (C) 2026 SpacemiT (Hangzhou) Technology Co. Ltd.
 * SPDX-License-Identifier: Apache-2.0
 */

#include <algorithm>
#include <cmath>
#include <deque>
#include <memory>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#include "action_recognition/msg/action_array.hpp"
#include "body_pose/msg/body_pose_array.hpp"
#include "rclcpp/rclcpp.hpp"
#include "vision_service.h"

#include "ament_index_cpp/get_package_share_directory.hpp"

namespace {

constexpr int kSequenceLength = 30;
constexpr int kStgcnNumKeypoints = 13;
// COCO 17 -> TSSTG/STGCN 13 (same as model_zoo fall_detection)
constexpr int kCoco17ToTsstg13[] = {0, 5, 6, 7, 8, 9, 10, 11, 12, 1, 2, 3, 4};

struct PersonBuffer {
    std::deque<std::vector<float>> frames;
    uint32_t person_id = 0;
};

// Build one frame of 13 keypoints (x, y, vis) for STGCN from BodyPose keypoints (17 COCO).
std::vector<float> KeypointsToStgcnFrame(const body_pose::msg::BodyPose& pose) {
    std::vector<float> frame(static_cast<size_t>(kStgcnNumKeypoints * 3), 0.f);
    if (pose.keypoints.size() < 17u) return frame;
    for (int i = 0; i < kStgcnNumKeypoints; ++i) {
        int idx = kCoco17ToTsstg13[i];
        const auto& kp = pose.keypoints[static_cast<size_t>(idx)];
        frame[static_cast<size_t>(i * 3 + 0)] = kp.position.x;
        frame[static_cast<size_t>(i * 3 + 1)] = kp.position.y;
        frame[static_cast<size_t>(i * 3 + 2)] = kp.confidence;
    }
    return frame;
}

// Flatten 30 frames of 13*3 into pts for InferSequence.
std::vector<float> BufferToPts(const std::deque<std::vector<float>>& buffer) {
    const size_t need = static_cast<size_t>(kSequenceLength * kStgcnNumKeypoints * 3);
    std::vector<float> pts(need, 0.f);
    size_t off = 0;
    for (const auto& frame : buffer) {
        size_t n = std::min(frame.size(), static_cast<size_t>(kStgcnNumKeypoints * 3));
        for (size_t i = 0; i < n; ++i) pts[off + i] = frame[i];
        off += static_cast<size_t>(kStgcnNumKeypoints * 3);
    }
    return pts;
}

// Match current poses to previous slots by bbox center distance; return slot index per pose.
std::vector<int> MatchPosesToSlots(
    const std::vector<std::pair<float, float>>& prev_centers,
    const body_pose::msg::BodyPoseArray::SharedPtr& msg) {
    std::vector<int> assign(msg->poses.size(), -1);
    std::vector<bool> used(prev_centers.size(), false);
    for (size_t p = 0; p < msg->poses.size(); ++p) {
        float cx = msg->poses[p].bbox.x_offset + msg->poses[p].bbox.width * 0.5f;
        float cy = msg->poses[p].bbox.y_offset + msg->poses[p].bbox.height * 0.5f;
        int best = -1;
        float best_d2 = 1e30f;
        for (size_t s = 0; s < prev_centers.size(); ++s) {
            if (used[s]) continue;
            float dx = cx - prev_centers[s].first;
            float dy = cy - prev_centers[s].second;
            float d2 = dx * dx + dy * dy;
            if (d2 < best_d2) {
                best_d2 = d2;
                best = static_cast<int>(s);
            }
        }
        if (best >= 0) {
            assign[p] = best;
            used[static_cast<size_t>(best)] = true;
        }
    }
    return assign;
}

}  // namespace

class ActionRecognitionNode : public rclcpp::Node {
    public:
    ActionRecognitionNode() : Node("action_recognition_node") {
        std::string config_path = declare_parameter<std::string>("config_path", "");
        const bool lazy_load = declare_parameter<bool>("lazy_load", true);
        body_poses_topic_ = declare_parameter<std::string>("body_poses_topic", "/perception/body_poses");
        actions_topic_ = declare_parameter<std::string>("actions_topic", "/perception/actions");
        sequence_length_ = declare_parameter<int>("sequence_length", kSequenceLength);
        infer_interval_ = declare_parameter<int>("infer_interval", 10);
        score_threshold_ = declare_parameter<double>("score_threshold", 0.25);
        max_persons_ = declare_parameter<int>("max_persons", 10);
        use_upstream_track_id_ = declare_parameter<bool>("use_upstream_track_id", false);
        image_width_ = declare_parameter<int>("image_width", 640);
        image_height_ = declare_parameter<int>("image_height", 480);

        if (config_path.empty()) {
            config_path = GetDefaultStgcnConfigPath();
        }
        if (config_path.empty()) {
            throw std::runtime_error(
                "config_path is empty. Set config_path to STGCN model yaml "
                "(e.g. share/action_recognition/config/stgcn.yaml)");
        }

        service_ = VisionService::Create(config_path, "", lazy_load);
        if (!service_) {
            throw std::runtime_error(
                "VisionService::Create failed: " + VisionService::LastCreateError());
        }
        class_names_ = service_->GetSequenceClassNames();
        if (class_names_.empty()) {
            throw std::runtime_error("STGCN model did not return class names");
        }

        actions_pub_ = create_publisher<action_recognition::msg::ActionArray>(actions_topic_, 10);
        body_poses_sub_ = create_subscription<body_pose::msg::BodyPoseArray>(
            body_poses_topic_,
            rclcpp::SensorDataQoS(),
            std::bind(&ActionRecognitionNode::OnBodyPoses, this, std::placeholders::_1));

        RCLCPP_INFO(
            get_logger(),
            "action_recognition_node started, body_poses=%s, actions=%s",
            body_poses_topic_.c_str(),
            actions_topic_.c_str());
    }

    private:
    static std::string GetDefaultStgcnConfigPath() {
        try {
            return ament_index_cpp::get_package_share_directory("action_recognition") +
                    "/config/stgcn.yaml";
        } catch (...) {
            return "";
        }
    }

    void OnBodyPoses(const body_pose::msg::BodyPoseArray::SharedPtr msg) {
        if (msg->poses.empty()) {
            prev_centers_.clear();
            empty_frame_count_++;
            // Clear buffer only after consecutive frames without pose (avoid single-frame miss)
            if (empty_frame_count_ >= 15) {
                slot_buffers_.clear();
            }
            return;
        }
        empty_frame_count_ = 0;
        frame_count_++;
        RCLCPP_DEBUG_THROTTLE(
            get_logger(),
            *get_clock(),
            2000,
            "body_poses: %zu poses, frame=%u, buffers=%zu",
            msg->poses.size(),
            frame_count_,
            slot_buffers_.size());

        // Current bbox centers for matching
        std::vector<std::pair<float, float>> curr_centers;
        for (const auto& p : msg->poses) {
            float cx = p.bbox.x_offset + p.bbox.width * 0.5f;
            float cy = p.bbox.y_offset + p.bbox.height * 0.5f;
            curr_centers.emplace_back(cx, cy);
        }

        // Match to previous slots: optionally use upstream track_id, otherwise center-distance
        std::vector<int> slot_for_pose(msg->poses.size(), -1);
        bool has_upstream_track = false;
        if (use_upstream_track_id_) {
            for (const auto& p : msg->poses) {
                if (p.track_id >= 0) {
                    has_upstream_track = true;
                    break;
                }
            }
        }

        if (has_upstream_track) {
            // Use upstream track_id as slot key when available
            for (size_t i = 0; i < msg->poses.size(); ++i) {
                int tid = msg->poses[i].track_id;
                if (tid < 0) continue;
                int slot = tid % max_persons_;
                if (slot_buffers_.find(slot) == slot_buffers_.end()) {
                    slot_buffers_[slot] = PersonBuffer();
                    slot_buffers_[slot].person_id = static_cast<uint32_t>(tid);
                }
                slot_for_pose[i] = slot;
            }
        } else {
            // fallback: bbox center distance matching
            std::vector<int> pose_to_slot = MatchPosesToSlots(prev_centers_, msg);
            for (size_t i = 0; i < msg->poses.size(); ++i) {
                int s = pose_to_slot[i];
                if (s >= 0) {
                    slot_for_pose[i] = s;
                } else {
                    for (int k = 0; k < max_persons_; ++k) {
                        if (slot_buffers_.find(k) == slot_buffers_.end()) {
                            slot_buffers_[k] = PersonBuffer();
                            slot_buffers_[k].person_id = next_person_id_++;
                            slot_for_pose[i] = k;
                            break;
                        }
                    }
                }
            }
        }

        prev_centers_.swap(curr_centers);

        action_recognition::msg::ActionArray out;
        out.header = msg->header;
        out.actions.clear();

        for (size_t i = 0; i < msg->poses.size(); ++i) {
            const auto& pose = msg->poses[i];
            if (pose.confidence < static_cast<float>(score_threshold_)) continue;
            if (pose.keypoints.size() < 17u) continue;

            int slot = slot_for_pose[i];
            if (slot < 0) continue;

            PersonBuffer& buf = slot_buffers_[slot];
            std::vector<float> frame = KeypointsToStgcnFrame(pose);
            buf.frames.push_back(std::move(frame));
            while (buf.frames.size() > static_cast<size_t>(sequence_length_)) {
                buf.frames.pop_front();
            }


            if (buf.frames.size() == static_cast<size_t>(sequence_length_) &&
                (frame_count_ % std::max(1, infer_interval_) == 0)) {
                std::vector<float> pts = BufferToPts(buf.frames);
                std::vector<float> scores;
                if (service_->InferSequence(pts.data(), image_width_, image_height_, &scores) ==
                        VISION_SERVICE_OK &&
                    !scores.empty()) {
                    size_t pred = static_cast<size_t>(
                        std::max_element(scores.begin(), scores.end()) - scores.begin());
                    float conf = scores[pred];
                    std::string name =
                        (pred < class_names_.size()) ? class_names_[pred] : "Unknown";

                    action_recognition::msg::Action action;
                    action.person_id = buf.person_id;
                    action.action_name = name;
                    action.confidence = conf;
                    action.start_frame =
                        frame_count_ - static_cast<uint32_t>(sequence_length_ - 1);
                    action.end_frame = frame_count_;
                    out.actions.push_back(action);
                    RCLCPP_DEBUG(
                        get_logger(),
                        "STGCN: person_id=%u action=%s conf=%.2f",
                        buf.person_id,
                        name.c_str(),
                        conf);
                } else {
                    RCLCPP_WARN_THROTTLE(
                        get_logger(),
                        *get_clock(),
                        3000,
                        "InferSequence failed or empty: %s",
                        service_->LastError().c_str());
                }
            }
        }

        // Prune stale slots (no match this frame)
        std::vector<int> to_remove;
        for (const auto& kv : slot_buffers_) {
            const int slot = kv.first;
            bool matched = false;
            for (int s : slot_for_pose) {
                if (s == slot) {
                    matched = true;
                    break;
                }
            }
            if (!matched) to_remove.push_back(slot);
        }
        for (int s : to_remove) slot_buffers_.erase(s);

        // Always publish (empty actions when no result) so downstream sees data flow
        actions_pub_->publish(out);
    }

    std::unique_ptr<VisionService> service_;
    std::vector<std::string> class_names_;
    double score_threshold_{0.25};
    std::string body_poses_topic_;
    std::string actions_topic_;
    int sequence_length_{kSequenceLength};
    int infer_interval_{10};
    int max_persons_{10};
    bool use_upstream_track_id_{false};
    int image_width_{640};
    int image_height_{480};
    uint32_t frame_count_{0};
    uint32_t next_person_id_{0};
    int empty_frame_count_{0};
    std::vector<std::pair<float, float>> prev_centers_;
    std::unordered_map<int, PersonBuffer> slot_buffers_;

    rclcpp::Publisher<action_recognition::msg::ActionArray>::SharedPtr actions_pub_;
    rclcpp::Subscription<body_pose::msg::BodyPoseArray>::SharedPtr body_poses_sub_;
};

int main(int argc, char** argv) {
    rclcpp::init(argc, argv);
    try {
        rclcpp::spin(std::make_shared<ActionRecognitionNode>());
    } catch (const std::exception& e) {
        RCLCPP_ERROR(rclcpp::get_logger("action_recognition_node"), "Exception: %s", e.what());
        rclcpp::shutdown();
        return 1;
    }
    rclcpp::shutdown();
    return 0;
}
