require "rails_helper"

RSpec.describe RubyCore::DiffValidator do
  it "accepts exactly one changed line" do
    old_content = "a\nb\nc\n"
    new_content = "a\nB\nc\n"

    result = described_class.validate_one_line_change!(old_content: old_content, new_content: new_content)
    expect(result[:changed_line_number]).to eq(2)
  end

  it "rejects zero changes" do
    content = "a\n"
    expect do
      described_class.validate_one_line_change!(old_content: content, new_content: content)
    end.to raise_error(RubyCore::DiffValidator::ValidationError, /no changes/i)
  end

  it "rejects multiple line changes" do
    old_content = "a\nb\nc\n"
    new_content = "A\nB\nc\n"
    expect do
      described_class.validate_one_line_change!(old_content: old_content, new_content: new_content)
    end.to raise_error(RubyCore::DiffValidator::ValidationError, /more than one line/i)
  end
end

