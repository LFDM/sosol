require 'fileutils'

class Grit::Commit
  def to_hash
    return {
      :id => @id,
      # Default for this is just first 7 chars
      # :id_abbrev => id_abbrev,
      :author_name => @author.name,
      :author_email => @author.email,
      :authored_date => @authored_date,
      :committer_name => @committer.name,
      :committer_email => @committer.email,
      :committed_date => @committed_date,
      :message => @message
    }
  end
end

class Repository
  attr_reader :master, :path, :repo
  
  # Allow Repository instances to be created outside User context.
  # These instances will only work with the canonical repo.
  def initialize(master = nil)
    @master = master
    if master.nil?
      @path = CANONICAL_REPOSITORY
    else
      @master_class_path = @master.class.to_s.underscore.pluralize
      if @master.class == Board
        unless @master.community.nil?
          @master_class_path = File.join('communities', @master.community.name)
        end
      end
      FileUtils.mkdir_p(File.join(REPOSITORY_ROOT, @master_class_path))
      
      @path = File.join(REPOSITORY_ROOT,
                        @master_class_path, "#{master.name}.git")
    end
    
    @canonical = Grit::Repo.new(CANONICAL_REPOSITORY)
    if master.nil? || exists?(path)
      @repo = Grit::Repo.new(path)
    else
      @repo = nil
    end
  end
  
  def owner
    return @master
  end
  
  def exists?(path)
    # master.has_repository?
    File.exists?(path)
  end

  def create
    # master.update_attribute :has_repository, true
    # create a git repository
    @repo ||= @canonical.fork_bare(path)
  end
  
  def destroy
    # master.update_attribute :has_repository, false
    # destroy a git repository
    
    # BEFORE DELETION: REPACK CANONICAL
    # This will pull in all objects regardless of alternates/shared status.
    # If you delete an alternates-referenced repository without repacking,
    # referenced objects will disappear, possibly making the repo unusable.
    @canonical.git.repack({})
    
    canon = Repository.new
    canon.del_alternates(self)
    FileUtils::rm_r path, :verbose => false
  end
  
  #returns the blob that represents the given file
  #the given file is the filename + path to the file
  def get_blob_from_branch(file, branch = 'master')
    begin
      #get the tree for the file's directory
      tree = @repo.tree(branch, [File.dirname(file)])
      subtree = tree.contents.first
      return nil if subtree.nil?
      #get the named object (file's base name) from tree
      blob = subtree / File.basename(file)
    rescue Grit::GitRuby::Repository::NoSuchPath
      return nil
    end
  end
  
  def get_file_from_branch(file, branch = 'master')  
    blob = get_blob_from_branch(file, branch)
    return get_blob_data(blob)
  end
  
  def get_blob_data(blob)
    begin
      # blob.data gets INSANELY slow for large files in a large repo,
      # this uses @repo.git.show to call a git command instead:
      #   slower than I would like but still an order of magnitude
      #   faster (for an example see e.g.
      #   DDB_EpiDoc_XML/p.mich/p.mich.4.1/p.mich.4.1.224.xml)
      # data = blob.nil? ? nil : @repo.git.show({}, blob.id.to_s)
      # BALMAS -> above problem was addressed via a patch to the GRIT modules
      # should should be okay now to cal blob.data
      data = blob.nil? ? nil : blob.data
      return data
    rescue Grit::Git::GitTimeout
      self.class.increase_timeout
      get_blob_data(blob)
    end
  end
  
  def get_all_files_from_path_on_branch(path = '', branch = 'master')
    root_tree = @repo.tree(branch, [path]).contents.first
    return recurse_git_tree(root_tree, [path])
  end
  
  def recurse_git_tree(tree, path)
    files = []
    tree.blobs.each do |blob|
      files << File.join(path, blob.name)
    end
    tree.trees.each do |this_tree|
      path.push(this_tree.name)
      files += recurse_git_tree(this_tree, path)
      path.pop
    end
    return files
  end
  
  def get_log_for_file_from_branch(file, branch = 'master')
    @repo.log(branch, file, :follow => true).map{|commit| commit.to_hash}
  end
  
  def update_master_from_canonical
    @repo.update_ref('master',@canonical.get_head('master').commit.id)
  end
  
  def create_branch(name, source_name = 'master')
    # We always assume we want to branch from master by default
    if source_name == 'master'
      self.update_master_from_canonical
      source_name = @repo.get_head(source_name).commit.id
    end
    
    @repo.update_ref(name, source_name)
  end
  
  def delete_branch(name)
    @repo.git.fs_delete("refs/heads/#{name}")
  end
  
  #(from_branch, to_branch, from_repo)
  def copy_branch_from_repo(branch, new_branch, other_repo)
    # Lightweight (but have to watch out for side-effects of repo deletion):
    # self.add_alternates(other_repo)
    # Heavyweight (missing objects are actually copied):
    self.fetch_objects(other_repo)
    
    head_ref = other_repo.repo.get_head(branch).commit.sha
    self.create_branch(new_branch, head_ref)
  end
  
  def add_remote(other_repo)
    unless @repo.remote_list.include?(other_repo.name)
      @repo.remote_add(other_repo.name, other_repo.path)
    end
  end
  
  def fetch_objects(other_repo)
    self.add_remote(other_repo)
    begin
      @repo.remote_fetch(other_repo.name)
    rescue Grit::Git::GitTimeout
      self.class.increase_timeout
      fetch_objects(other_repo)
    end
  end
  
  def name
    return [@master_class_path, @master.name].join('/').tr(' ', '_')
  end
  
  def add_alternates(other_repo)
    @repo.alternates = @repo.alternates() | [ File.join(other_repo.repo.path, "objects") ]
  end
  
  def del_alternates(other_repo)
    @repo.alternates = @repo.alternates() - [ File.join(other_repo.repo.path, "objects") ]
  end
  
  def branches
    @repo.branches.map{|b| b.name}
  end
  
  def rename_file(original_path, new_path, branch, comment, actor)
    content = get_file_from_branch(original_path, branch)
    if !content
      raise "Rename error: Original file '#{original_path}' does not exist on branch '#{branch}'"
    elsif get_blob_from_branch(new_path, branch)
      raise "Rename error: Destination file '#{new_path}' already exists on branch '#{branch}'"
    end
    
    index = @repo.index
    index.read_tree(branch)
    # do the rename here, against index.tree
    # rename is just a simultaneous add/delete
    # add the new data
    index.add(new_path, content)
    # remove the old path from the tree
    index.rm(original_path)

    index.commit(comment,
                 @repo.commits(branch,1).first.to_s, # commit parent,
                 actor,
                 nil,
                 branch)
  end
  
  # Returns a String of the SHA1 of the commit
  def commit_content(file, branch, data, comment, actor = nil)
    if @path == CANONICAL_REPOSITORY
      raise "Cannot commit directly to canonical repository" unless (file == CollectionIdentifier.new.to_path)
    end
    
    index = @repo.index
    index.read_tree(branch)
    index.add(file, data)
    index.commit(comment,
                 @repo.commits(branch,1).first.to_s, # commit parent
                 actor,
                 nil,
                 branch)
  end
  
  def self.increase_timeout
    Grit::Git.git_timeout *= 2
    RAILS_DEFAULT_LOGGER.warn "Git timed out, increasing timeout to #{Grit::Git.git_timeout}"
  end
  
  def safe_repo_name(name)
    java.text.Normalizer.normalize(name.tr(' ','_'),java.text.Normalizer::Form::NFD).gsub(/\p{M}/,'')
  end
end
