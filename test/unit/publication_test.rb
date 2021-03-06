require 'test_helper'

class PublicationTest < ActiveSupport::TestCase
  context "a publication conflicting with an existing branch" do
    setup do
      @user = Factory(:user)
      
      @branchname = "testpublication"
      @user.repository.create_branch(@branchname)
      @publication = Factory.build(:publication, :owner => @user, :creator => @user, :title => @branchname)
    end
    
    teardown do
      @user.destroy
    end
    
    should "not be saved to the database" do
      assert !@publication.save
    end
  end
  
  context "a new publication from templates" do
    setup do
      @user = Factory(:user)
      @publication = Publication.new_from_templates(@user)
    end

    teardown do
      @publication.destroy unless !Publication.exists?(@publication.id)
      @user.destroy
    end
    
    should "exist" do
      assert Publication.exists?(@publication.id)
    end
    
    should "have an equivalent creator and owner" do
      assert_equal @publication.creator, @publication.owner
    end
    
    should "have a branch with its branch attribute" do
      assert @user.repository.branches.include?(@publication.branch)
    end
    
    should "delete its branch upon destruction" do
      publication_branch = @publication.branch
      @publication.destroy
      assert !@user.repository.branches.include?(publication_branch)
    end
    
    should "have valid XML for templates" do
      @publication.identifiers.each do |identifier|
        assert identifier.is_valid_xml?
      end
    end
    
    should "have status 'new'" do
      assert_equal "new", @publication.status
    end
    
    should "have a head" do
      assert @publication.head
    end

    should "not be able to create multiple new identifiers of the same class from templates" do
      @publication.reload
      original_identifiers_length = @publication.identifiers.length
      @publication.identifiers.each do |i|
        assert_nil i.class.new_from_template(@publication)
      end
      @publication.reload
      assert_equal original_identifiers_length, @publication.identifiers.length
    end
  end
  
  context "a publication copied to another owner" do
    setup do
      @original_owner = Factory(:user)
      @new_owner = Factory(:user)
      @publication = Publication.new_from_templates(@original_owner)
      @publication_copy = @publication.copy_to_owner(@new_owner)
    end
    
    teardown do
      @publication_copy.destroy
      @new_owner.destroy
      
      @publication.destroy
      @original_owner.destroy
    end
    
    should "retain the original creator" do
      assert_equal @publication_copy.creator, @original_owner
    end
    
    should "belong to the new owner" do
      assert_equal @publication_copy.owner, @new_owner
    end
    
    should "have its source as a parent" do
      assert_equal @publication_copy.parent, @publication
    end
    
    should "be a child of its parent" do
      assert @publication.children.include?(@publication_copy)
    end
  end
  
  context "a publication with unicode in its title/branch" do
    setup do
      @user = Factory(:user)
      @original_branches = @user.repository.branches
      
      @unicode_title = "P.Über βρεκεκεκέξ"
      @publication = Factory(:publication, :owner => @user, :creator => @user, :title => @unicode_title)
      @publication.branch_from_master
      
      @new_ddb = DDBIdentifier.new_from_template(@publication)
    end
    
    teardown do
      @publication.destroy unless !Publication.exists? @publication.id
      @user.destroy
    end
    
    should "have content" do
      assert @new_ddb.content
    end
    
    should "have the branch" do
      assert @user.repository.branches.include?(@publication.branch)
    end
    
    should "only have the original branches after deletion" do
      @publication.destroy
      assert_equal @original_branches.sort,@user.repository.branches.sort
    end
  end
end
