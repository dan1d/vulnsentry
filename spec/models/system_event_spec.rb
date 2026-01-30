# frozen_string_literal: true

require "rails_helper"

RSpec.describe SystemEvent, type: :model do
  describe "validations" do
    it "is valid with all required attributes" do
      event = described_class.new(
        kind: SystemEventKinds::ADVISORY_INGEST,
        status: "ok",
        message: "Test message",
        occurred_at: Time.current
      )
      expect(event).to be_valid
    end

    it "requires kind" do
      event = described_class.new(status: "ok", occurred_at: Time.current)
      expect(event).not_to be_valid
      expect(event.errors[:kind]).to include("can't be blank")
    end

    it "requires status" do
      event = described_class.new(kind: "test", occurred_at: Time.current)
      expect(event).not_to be_valid
      expect(event.errors[:status]).to include("can't be blank")
    end

    it "requires occurred_at" do
      event = described_class.new(kind: "test", status: "ok")
      expect(event).not_to be_valid
      expect(event.errors[:occurred_at]).to include("can't be blank")
    end

    it "validates status inclusion" do
      event = described_class.new(
        kind: "test",
        status: "invalid_status",
        occurred_at: Time.current
      )
      expect(event).not_to be_valid
      expect(event.errors[:status]).to include("is not included in the list")
    end

    it "accepts valid statuses" do
      %w[ok warning failed].each do |status|
        event = described_class.new(
          kind: "test",
          status: status,
          occurred_at: Time.current
        )
        expect(event).to be_valid
      end
    end
  end

  describe "STATUSES constant" do
    it "defines all valid statuses" do
      expect(described_class::STATUSES).to contain_exactly("ok", "warning", "failed")
    end
  end

  describe "class methods from SystemEventKinds" do
    it "provides kind_options_for_select" do
      options = described_class.kind_options_for_select
      expect(options).to be_an(Array)
      expect(options.map(&:last)).to include("advisory_ingest")
    end

    it "provides grouped_kind_options_for_select" do
      grouped = described_class.grouped_kind_options_for_select
      expect(grouped).to be_a(Hash)
      expect(grouped.keys).to include("Advisory", "Branch", "Evaluation", "Pull Request")
    end
  end

  describe "scopes" do
    before do
      @ok_event = create_event(status: "ok", kind: SystemEventKinds::ADVISORY_INGEST)
      @warning_event = create_event(status: "warning", kind: SystemEventKinds::BRANCH_REFRESH)
      @failed_event = create_event(status: "failed", kind: SystemEventKinds::CREATE_PR)
    end

    describe ".ok" do
      it "returns only ok events" do
        expect(described_class.ok).to contain_exactly(@ok_event)
      end
    end

    describe ".warnings" do
      it "returns only warning events" do
        expect(described_class.warnings).to contain_exactly(@warning_event)
      end
    end

    describe ".failed" do
      it "returns only failed events" do
        expect(described_class.failed).to contain_exactly(@failed_event)
      end
    end

    describe ".by_kind" do
      it "filters by kind" do
        expect(described_class.by_kind(SystemEventKinds::ADVISORY_INGEST)).to contain_exactly(@ok_event)
      end

      it "returns all when kind is blank" do
        expect(described_class.by_kind(nil).count).to eq(3)
        expect(described_class.by_kind("").count).to eq(3)
      end
    end

    describe ".by_status" do
      it "filters by status" do
        expect(described_class.by_status("ok")).to contain_exactly(@ok_event)
        expect(described_class.by_status("warning")).to contain_exactly(@warning_event)
        expect(described_class.by_status("failed")).to contain_exactly(@failed_event)
      end

      it "returns all when status is blank" do
        expect(described_class.by_status(nil).count).to eq(3)
      end
    end

    describe ".advisory_events" do
      it "returns only advisory-related events" do
        expect(described_class.advisory_events).to contain_exactly(@ok_event)
      end
    end

    describe ".branch_events" do
      it "returns only branch-related events" do
        expect(described_class.branch_events).to contain_exactly(@warning_event)
      end
    end

    describe ".pr_events" do
      it "returns only PR-related events" do
        expect(described_class.pr_events).to contain_exactly(@failed_event)
      end
    end
  end

  describe "time-based scopes" do
    before do
      @old_event = create_event(occurred_at: 10.days.ago)
      @recent_event = create_event(occurred_at: 2.hours.ago)
      @today_event = create_event(occurred_at: Time.current)
    end

    describe ".today" do
      it "returns only events from today" do
        expect(described_class.today).to include(@today_event, @recent_event)
        expect(described_class.today).not_to include(@old_event)
      end
    end

    describe ".last_24_hours" do
      it "returns events from the last 24 hours" do
        expect(described_class.last_24_hours).to include(@today_event, @recent_event)
        expect(described_class.last_24_hours).not_to include(@old_event)
      end
    end

    describe ".last_7_days" do
      it "returns events from the last 7 days" do
        expect(described_class.last_7_days).to include(@today_event, @recent_event)
        expect(described_class.last_7_days).not_to include(@old_event)
      end
    end

    describe ".recent" do
      it "returns events ordered by occurred_at desc with a limit" do
        result = described_class.recent(2)
        expect(result.count).to eq(2)
        expect(result.first).to eq(@today_event)
      end

      it "defaults to 50 limit" do
        expect(described_class.recent.limit_value).to eq(50)
      end
    end

    describe ".by_date_range" do
      it "filters by start date" do
        result = described_class.by_date_range(3.hours.ago)
        expect(result).to include(@today_event, @recent_event)
        expect(result).not_to include(@old_event)
      end

      it "filters by end date" do
        result = described_class.by_date_range(nil, 3.hours.ago)
        expect(result).to include(@old_event)
        expect(result).not_to include(@today_event)
      end

      it "filters by both start and end date" do
        result = described_class.by_date_range(5.days.ago, 1.day.ago)
        expect(result).not_to include(@today_event, @recent_event, @old_event)
      end

      it "returns all when both dates are blank" do
        expect(described_class.by_date_range(nil, nil).count).to eq(3)
      end
    end
  end

  describe "search scope" do
    before do
      @event_with_message = create_event(message: "rexml vulnerability found")
      @event_with_payload = create_event(
        message: "other message",
        payload: { gem_name: "nokogiri", version: "1.2.3" }
      )
      @unrelated_event = create_event(message: "unrelated")
    end

    describe ".search" do
      it "searches in message" do
        result = described_class.search("rexml")
        expect(result).to include(@event_with_message)
        expect(result).not_to include(@event_with_payload, @unrelated_event)
      end

      it "searches in payload" do
        result = described_class.search("nokogiri")
        expect(result).to include(@event_with_payload)
        expect(result).not_to include(@event_with_message, @unrelated_event)
      end

      it "is case-insensitive" do
        result = described_class.search("REXML")
        expect(result).to include(@event_with_message)
      end

      it "returns all when query is blank" do
        expect(described_class.search(nil).count).to eq(3)
        expect(described_class.search("").count).to eq(3)
      end
    end
  end

  describe "payload scopes" do
    before do
      @rexml_event = create_event(payload: { gem_name: "rexml", branch: "master" })
      @nokogiri_event = create_event(payload: { gem_name: "nokogiri", branch: "ruby_3_3" })
      @no_gem_event = create_event(payload: { other: "data" })
    end

    describe ".for_gem" do
      it "filters by gem_name in payload" do
        expect(described_class.for_gem("rexml")).to contain_exactly(@rexml_event)
        expect(described_class.for_gem("nokogiri")).to contain_exactly(@nokogiri_event)
      end

      it "returns all when gem_name is blank" do
        expect(described_class.for_gem(nil).count).to eq(3)
      end
    end

    describe ".for_branch" do
      it "filters by branch in payload" do
        expect(described_class.for_branch("master")).to contain_exactly(@rexml_event)
        expect(described_class.for_branch("ruby_3_3")).to contain_exactly(@nokogiri_event)
      end

      it "returns all when branch is blank" do
        expect(described_class.for_branch(nil).count).to eq(3)
      end
    end
  end

  describe "ordering scopes" do
    before do
      @first = create_event(occurred_at: 3.days.ago)
      @second = create_event(occurred_at: 2.days.ago)
      @third = create_event(occurred_at: 1.day.ago)
    end

    describe ".chronological" do
      it "orders by occurred_at ascending" do
        result = described_class.chronological
        expect(result.to_a).to eq([ @first, @second, @third ])
      end
    end

    describe ".reverse_chronological" do
      it "orders by occurred_at descending" do
        result = described_class.reverse_chronological
        expect(result.to_a).to eq([ @third, @second, @first ])
      end
    end
  end

  describe "instance methods" do
    describe "#ok?" do
      it "returns true for ok status" do
        event = described_class.new(status: "ok")
        expect(event.ok?).to be true
      end

      it "returns false for other statuses" do
        event = described_class.new(status: "warning")
        expect(event.ok?).to be false
      end
    end

    describe "#warning?" do
      it "returns true for warning status" do
        event = described_class.new(status: "warning")
        expect(event.warning?).to be true
      end

      it "returns false for other statuses" do
        event = described_class.new(status: "ok")
        expect(event.warning?).to be false
      end
    end

    describe "#failed?" do
      it "returns true for failed status" do
        event = described_class.new(status: "failed")
        expect(event.failed?).to be true
      end

      it "returns false for other statuses" do
        event = described_class.new(status: "ok")
        expect(event.failed?).to be false
      end
    end

    describe "#gem_name" do
      it "returns gem_name from payload" do
        event = described_class.new(payload: { "gem_name" => "rexml" })
        expect(event.gem_name).to eq("rexml")
      end

      it "returns nil when not in payload" do
        event = described_class.new(payload: {})
        expect(event.gem_name).to be_nil
      end
    end

    describe "#branch" do
      it "returns branch from payload" do
        event = described_class.new(payload: { "branch" => "master" })
        expect(event.branch).to eq("master")
      end

      it "returns nil when not in payload" do
        event = described_class.new(payload: {})
        expect(event.branch).to be_nil
      end
    end
  end

  private

  def create_event(overrides = {})
    described_class.create!({
      kind: SystemEventKinds::ADVISORY_INGEST,
      status: "ok",
      message: "Test event",
      payload: {},
      occurred_at: Time.current
    }.merge(overrides))
  end
end
