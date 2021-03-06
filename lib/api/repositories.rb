require 'mime/types'

module API
  # Projects API
  class Repositories < Grape::API
    before { authenticate! }
    before { authorize! :download_code, user_project }

    resource :projects do
      helpers do
        def handle_project_member_errors(errors)
          if errors[:project_access].any?
            error!(errors[:project_access], 422)
          end
          not_found!
        end
      end

      # Get a project repository tree
      #
      # Parameters:
      #   id (required) - The ID of a project
      #   ref_name (optional) - The name of a repository branch or tag, if not given the default branch is used
      #   recursive (optional) - Used to get a recursive tree
      # Example Request:
      #   GET /projects/:id/repository/tree
      get ':id/repository/tree' do
        ref = params[:ref_name] || user_project.try(:default_branch) || 'master'
        path = params[:path] || nil
        recursive = to_boolean(params[:recursive])

        commit = user_project.commit(ref)
        not_found!('Tree') unless commit

        tree = user_project.repository.tree(commit.id, path, recursive: recursive)

        present tree.sorted_entries, with: Entities::RepoTreeObject
      end

      # Get a raw file contents
      #
      # Parameters:
      #   id (required) - The ID of a project
      #   sha (required) - The commit or branch name
      #   filepath (required) - The path to the file to display
      # Example Request:
      #   GET /projects/:id/repository/blobs/:sha
      get [ ":id/repository/blobs/:sha", ":id/repository/commits/:sha/blob" ] do
        required_attributes! [:filepath]

        ref = params[:sha]

        repo = user_project.repository

        commit = repo.commit(ref)
        not_found! "Commit" unless commit

        blob = Gitlab::Git::Blob.find(repo, commit.id, params[:filepath])
        not_found! "File" unless blob

        send_git_blob repo, blob
      end

      # Get a raw blob contents by blob sha
      #
      # Parameters:
      #   id (required) - The ID of a project
      #   sha (required) - The blob's sha
      # Example Request:
      #   GET /projects/:id/repository/raw_blobs/:sha
      get ':id/repository/raw_blobs/:sha' do
        ref = params[:sha]

        repo = user_project.repository

        begin
          blob = Gitlab::Git::Blob.raw(repo, ref)
        rescue
          not_found! 'Blob'
        end

        not_found! 'Blob' unless blob

        send_git_blob repo, blob
      end

      # Get a an archive of the repository
      #
      # Parameters:
      #   id (required) - The ID of a project
      #   sha (optional) - the commit sha to download defaults to the tip of the default branch
      # Example Request:
      #   GET /projects/:id/repository/archive
      get ':id/repository/archive',
          requirements: { format: Gitlab::Regex.archive_formats_regex } do
        authorize! :download_code, user_project

        begin
          send_git_archive user_project.repository, ref: params[:sha], format: params[:format]
        rescue
          not_found!('File')
        end
      end

      # Compare two branches, tags or commits
      #
      # Parameters:
      #   id (required) - The ID of a project
      #   from (required) - the commit sha or branch name
      #   to (required) - the commit sha or branch name
      # Example Request:
      #   GET /projects/:id/repository/compare?from=master&to=feature
      get ':id/repository/compare' do
        authorize! :download_code, user_project
        required_attributes! [:from, :to]
        compare = Gitlab::Git::Compare.new(user_project.repository.raw_repository, params[:from], params[:to])
        present compare, with: Entities::Compare
      end

      # Get repository contributors
      #
      # Parameters:
      #   id (required) - The ID of a project
      # Example Request:
      #   GET /projects/:id/repository/contributors
      get ':id/repository/contributors' do
        authorize! :download_code, user_project

        begin
          present user_project.repository.contributors,
                  with: Entities::Contributor
        rescue
          not_found!
        end
      end
    end
  end
end
