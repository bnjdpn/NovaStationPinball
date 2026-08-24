# frozen_string_literal: true

require "minitest/autorun"
require_relative "wait_for_state"

class NovaStationPinballStateWaiterTest < Minitest::Test
  def test_waits_with_get_only_until_the_exact_target_build_is_valid
    payloads = [payload(build_state: "PROCESSING"), payload(build_state: "VALID")]
    clock = [0.0, 0.0, 1.0]
    reads = 0
    result = NovaStationPinballStateWaiter.wait(
      reader: -> { reads += 1; payloads.shift },
      condition: "build", version: "1.0", timeout: 10, interval: 2,
      monotonic: -> { clock.shift }, sleeper: ->(_seconds) {}
    )
    assert_equal 2, reads
    assert_equal "VALID", result.fetch("recent_builds").first.fetch("state")
  end

  def test_failed_media_and_build_states_fail_immediately
    media = payload(build_state: "PROCESSING")
    media.fetch("assets")["failed"] = [{ "state" => "FAILED" }]
    assert_raises(NovaStationPinballStateWaiter::FailedState) do
      NovaStationPinballStateWaiter.wait(
        reader: -> { media }, condition: "previews", version: "1.0",
        timeout: 10, interval: 1
      )
    end
    assert_raises(NovaStationPinballStateWaiter::FailedState) do
      NovaStationPinballStateWaiter.wait(
        reader: -> { payload(build_state: "INVALID") },
        condition: "build", version: "1.0", timeout: 10, interval: 1
      )
    end
  end

  def test_timeout_never_invokes_a_mutation_callback
    clock = [0.0, 0.0, 3.0]
    reads = 0
    assert_raises(NovaStationPinballStateWaiter::TimeoutError) do
      NovaStationPinballStateWaiter.wait(
        reader: -> { reads += 1; payload(build_state: "PROCESSING") },
        condition: "build", version: "1.0", timeout: 3, interval: 1,
        monotonic: -> { clock.shift }, sleeper: ->(_seconds) {}
      )
    end
    assert_equal 2, reads
  end

  def test_rejected_submission_is_not_reported_as_submitted
    rejected = payload(build_state: "VALID")
    rejected.fetch("version")["state"] = "UNRESOLVED_ISSUES"
    rejected.fetch("review_submissions") << {
      "state" => "UNRESOLVED_ISSUES",
      "items" => [{ "version" => "1.0" }]
    }

    refute NovaStationPinballStateWaiter.complete?(
      rejected, "submitted", version: "1.0"
    )
  end

  def test_submitted_requires_the_app_leaderboard_and_workshop_resources
    submitted = payload(build_state: "VALID")
    submitted.fetch("version")["state"] = "WAITING_FOR_REVIEW"
    resources = [
      ["appStoreVersions", "version-1"],
      ["gameCenterLeaderboardVersions", "leaderboard-version-1"],
      ["inAppPurchaseVersions", "workshop-version-1"]
    ]
    submitted["required_review_resources"] = resources
    submitted.fetch("review_submissions") << {
      "state" => "WAITING_FOR_REVIEW",
      "items" => resources.map do |type, id|
        { "resource_type" => type, "resource_id" => id }
      end
    }

    assert NovaStationPinballStateWaiter.complete?(
      submitted, "submitted", version: "1.0"
    )
    submitted.fetch("review_submissions").first.fetch("items").delete_at(1)
    refute NovaStationPinballStateWaiter.complete?(
      submitted, "submitted", version: "1.0"
    )

    submitted.fetch("review_submissions").first["items"] = resources.map do |type, id|
      { "resource_type" => type, "resource_id" => id }
    end
    submitted.fetch("review_submissions").first.fetch("items") << {
      "resource_type" => "inAppPurchaseVersions",
      "resource_id" => "old-tip-version"
    }
    refute NovaStationPinballStateWaiter.complete?(
      submitted, "submitted", version: "1.0"
    )

    submitted.fetch("review_submissions").first["items"] = resources.map do |type, id|
      { "resource_type" => type, "resource_id" => id }
    end
    submitted.fetch("review_submissions") << {
      "state" => "READY_FOR_REVIEW", "items" => []
    }
    refute NovaStationPinballStateWaiter.complete?(
      submitted, "submitted", version: "1.0"
    )
  end

  private

  def payload(build_state:)
    {
      "target_build" => { "version" => "1.0", "build" => "7" },
      "recent_builds" => [
        { "build" => "7", "state" => build_state, "expired" => false }
      ],
      "selected_build" => nil,
      "metadata" => { "complete" => false },
      "assets" => {
        "screenshots_complete" => false,
        "previews_complete" => false,
        "failed" => []
      },
      "version" => { "version" => "1.0", "state" => "PREPARE_FOR_SUBMISSION" },
      "review_submissions" => []
    }
  end
end
