require "spec_helper"
require "bumper/dependency"
require "bumper/dependency_file"
require "bumper/pull_request_creator"

RSpec.describe PullRequestCreator do
  subject(:creator) do
    PullRequestCreator.new(repo: repo, dependency: dependency, files: files)
  end

  let(:dependency) { Dependency.new(name: "business", version: "1.5.0") }
  let(:repo) { "gocardless/bump" }
  let(:files) { [gemfile] }

  let(:gemfile) do
    DependencyFile.new(name: "Gemfile", content: fixture("Gemfile"))
  end
  let(:json_header) { { "Content-Type": "application/json" } }

  # Calls to GitHub to get info about the repo we're putting a PR into
  let(:repo_url) { "https://api.github.com/repos/#{repo}" }
  let(:bump_repo_response) { fixture("github", "bump_repo.json") }
  let(:ref_response) { fixture("github", "ref.json") }
  let(:create_ref_response) { fixture("github", "create_ref.json") }
  let(:create_ref_error_response) { fixture("github", "create_ref_error.json") }
  let(:update_file_response) { fixture("github", "update_file.json") }
  let(:create_pr_response) { fixture("github", "create_pr.json") }
  let(:gemfile_content_response) { fixture("github", "gemfile_content.json") }

  # Calls to Rubygems and GitHub to get info about the gem we're updating
  let(:rubygems_response) { fixture("rubygems_response.yaml") }
  let(:business_repo_url) { "https://api.github.com/repos/gocardless/business" }
  let(:business_repo_response) { fixture("github", "business_repo.json") }
  let(:business_files_response) { fixture("github", "business_files.json") }

  before do
    stub_request(:get, repo_url).
      to_return(status: 200,
                body: bump_repo_response,
                headers: json_header)
    stub_request(:get, "#{repo_url}/git/refs/heads/master").
      to_return(status: 200,
                body: ref_response,
                headers: json_header)
    stub_request(:post, "#{repo_url}/git/refs").
      to_return(status: 200,
                body: create_ref_response,
                headers: json_header)
    stub_request(:get, "#{repo_url}/contents/#{gemfile.name}").
      to_return(status: 200,
                body: gemfile_content_response,
                headers: json_header)
    stub_request(:put, "#{repo_url}/contents/#{gemfile.name}").
      to_return(status: 200,
                body: update_file_response,
                headers: json_header)
    stub_request(:post, "#{repo_url}/pulls").
      to_return(status: 200,
                body: create_pr_response,
                headers: json_header)

    stub_request(:get, business_repo_url).
      to_return(status: 200,
                body: business_repo_response,
                headers: json_header)
    stub_request(:get, "#{business_repo_url}/contents/").
      to_return(status: 200,
                body: business_files_response,
                headers: json_header)
    stub_request(:get, "https://rubygems.org/api/v1/gems/business.yaml").
      to_return(status: 200,
                body: rubygems_response,
                headers: json_header)
  end

  describe "#create" do
    it "creates a branch with the right name" do
      creator.create

      expect(WebMock).
        to have_requested(:post, "#{repo_url}/git/refs").
        with(body: {
               ref: "refs/heads/bump_business_to_1.5.0",
               sha: "aa218f56b14c9653891f9e74264a383fa43fefbd"
             })
    end

    it "pushes changes to that branch" do
      creator.create

      expect(WebMock).
        to have_requested(:put, "#{repo_url}/contents/Gemfile").
        with(body: {
               branch: "bump_business_to_1.5.0",
               sha: "dbce0c9e2e7efd19139c2c0aeb0110e837812c2f",
               content: "c291cmNlICJodHRwczovL3J1YnlnZW1zLm9yZyIKCmdlbSAiYnVza"\
                        "W5lc3MiLCAifj4gMS40LjAiCg==",
               message: "Updating Gemfile"
             })
    end

    it "creates a PR with the right details" do
      creator.create

      repo_url      = "https://api.github.com/repos/gocardless/bump"
      dep_url       = "https://github.com/gocardless/business"
      changelog_url = "https://api.github.com/repos/gocardless/business/"\
                      "contents/CHANGELOG.md?ref=master"
      commits_url   = "https://github.com/gocardless/business/commits"

      expect(WebMock).
        to have_requested(:post, "#{repo_url}/pulls").
        with(body: {
               base: "master",
               head: "bump_business_to_1.5.0",
               title: "Bump business to 1.5.0",
               body: "Bumps [business](#{dep_url}) to 1.5.0"\
                     "\n- [Changelog](#{changelog_url})"\
                     "\n- [Commits](#{commits_url})"
             })
    end

    context "when a branch for this update already exists" do
      before do
        stub_request(:post, "#{repo_url}/git/refs").
          to_return(status: 422,
                    body: create_ref_error_response,
                    headers: json_header)
      end

      specify { expect { creator.create }.to_not raise_error }

      it "doesn't push changes to the branch" do
        creator.create

        expect(WebMock).
          to_not have_requested(:put, "#{repo_url}/contents/Gemfile")
      end

      it "doesn't try to re-create the PR" do
        creator.create
        expect(WebMock).to_not have_requested(:post, "#{repo_url}/pulls")
      end
    end
  end
end