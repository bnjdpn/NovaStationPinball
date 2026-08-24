# frozen_string_literal: true

require "minitest/autorun"
require_relative "status"

class NovaStationPinballAscStatusTest < Minitest::Test
  class ReviewClient
    attr_reader :item_parameters

    def initialize(items)
      @items = items
    end

    def get_all(path, parameters = {})
      case path
      when "/v1/apps/app-1/reviewSubmissions"
        {
          "data" => [{
            "type" => "reviewSubmissions",
            "id" => "submission-1",
            "attributes" => {
              "state" => "WAITING_FOR_REVIEW",
              "submittedDate" => "2026-08-23T00:00:00Z"
            }
          }]
        }
      when "/v1/reviewSubmissions/submission-1/items"
        @item_parameters = parameters
        {
          "data" => @items,
          "included" => [{
            "type" => "appStoreVersions",
            "id" => "version-1",
            "attributes" => {
              "versionString" => "1.0", "appStoreState" => "WAITING_FOR_REVIEW"
            }
          }]
        }
      else
        raise "unexpected GET collection #{path}"
      end
    end
  end

  def test_review_submission_readback_includes_all_three_resource_types
    client = ReviewClient.new([
      review_item("item-app", "appStoreVersion", "appStoreVersions", "version-1"),
      review_item(
        "item-gc", "gameCenterLeaderboardVersion",
        "gameCenterLeaderboardVersions", "leaderboard-version-1"
      ),
      review_item(
        "item-iap", "inAppPurchaseVersion",
        "inAppPurchaseVersions", "workshop-version-1"
      )
    ])

    submissions = NovaStationPinballAscStatus.review_submissions(client, "app-1")

    resources = submissions.first.fetch("items").map do |item|
      [item.fetch("resource_type"), item.fetch("resource_id")]
    end
    assert_equal [
      ["appStoreVersions", "version-1"],
      ["gameCenterLeaderboardVersions", "leaderboard-version-1"],
      ["inAppPurchaseVersions", "workshop-version-1"]
    ], resources
    assert_includes client.item_parameters.fetch("include"),
                    "gameCenterLeaderboardVersion"
    assert_includes client.item_parameters.fetch("fields[reviewSubmissionItems]"),
                    "gameCenterLeaderboardVersion"
  end

  def test_review_item_with_missing_or_ambiguous_relationships_fails_closed
    missing = { "type" => "reviewSubmissionItems", "id" => "missing" }
    assert_raises(RuntimeError) do
      NovaStationPinballAscStatus.review_submissions(
        ReviewClient.new([missing]), "app-1"
      )
    end

    ambiguous = review_item(
      "ambiguous", "appStoreVersion", "appStoreVersions", "version-1"
    )
    ambiguous.fetch("relationships")["gameCenterLeaderboardVersion"] = {
      "data" => {
        "type" => "gameCenterLeaderboardVersions", "id" => "leaderboard-version-1"
      }
    }
    assert_raises(RuntimeError) do
      NovaStationPinballAscStatus.review_submissions(
        ReviewClient.new([ambiguous]), "app-1"
      )
    end
  end

  def test_submitted_readback_requires_app_leaderboard_and_workshop
    required = [
      ["appStoreVersions", "version-1"],
      ["gameCenterLeaderboardVersions", "leaderboard-version-1"],
      ["inAppPurchaseVersions", "workshop-version-1"]
    ]
    payload = {
      "version" => { "version" => "1.0", "state" => "WAITING_FOR_REVIEW" },
      "required_review_resources" => required,
      "review_submissions" => [{
        "state" => "WAITING_FOR_REVIEW",
        "items" => required.map do |type, id|
          { "resource_type" => type, "resource_id" => id }
        end
      }]
    }
    assert NovaStationPinballAscStatus.submitted?(payload, "1.0")

    payload.fetch("review_submissions").first.fetch("items").delete_at(1)
    refute NovaStationPinballAscStatus.submitted?(payload, "1.0")
  end

  private

  def review_item(id, relationship, type, resource_id)
    {
      "type" => "reviewSubmissionItems",
      "id" => id,
      "attributes" => { "state" => "READY_FOR_REVIEW" },
      "relationships" => {
        relationship => { "data" => { "type" => type, "id" => resource_id } }
      }
    }
  end
end
