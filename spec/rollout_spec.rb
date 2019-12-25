require "spec_helper"

RSpec.describe "Rollout" do
  before do
    @redis   = Redis.new
    @rollout = Rollout.new(@redis)
  end

  describe "when a group is activated" do
    before do
      @rollout.define_group(:fivesonly) { |user| user.id == 5 }
      @rollout.activate_group(:chat, :fivesonly)
    end

    it "the feature is active for users for which the block evaluates to true" do
      expect(@rollout).to be_active(:chat, double(id: 5))
    end

    it "is not active for users for which the block evaluates to false" do
      expect(@rollout).not_to be_active(:chat, double(id: 1))
    end

    it "is not active if a group is found in Redis but not defined in Rollout" do
      @rollout.activate_group(:chat, :fake)
      expect(@rollout).not_to be_active(:chat, double(id: 1))
    end
  end

  describe "the default all group" do
    before do
      @rollout.activate_group(:chat, :all)
    end

    it "evaluates to true no matter what" do
      expect(@rollout).to be_active(:chat, double(id: 0))
    end
  end

  describe "deactivating a group" do
    before do
      @rollout.define_group(:fivesonly) { |user| user.id == 5 }
      @rollout.activate_group(:chat, :all)
      @rollout.activate_group(:chat, :some)
      @rollout.activate_group(:chat, :fivesonly)
      @rollout.deactivate_group(:chat, :all)
      @rollout.deactivate_group(:chat, "some")
    end

    it "deactivates the rules for that group" do
      expect(@rollout).not_to be_active(:chat, double(id: 10))
    end

    it "leaves the other groups active" do
      expect(@rollout.get(:chat).groups).to eq [:fivesonly]
    end

    it "leaves the other groups active using sets" do
      @options = @rollout.instance_variable_get("@options")
      @options[:use_sets] = true
      expect(@rollout.get(:chat).groups).to eq [:fivesonly].to_set
    end
  end

  describe "deactivating a feature completely" do
    before do
      @rollout.define_group(:fivesonly) { |user| user.id == 5 }
      @rollout.activate_group(:chat, :all)
      @rollout.activate_group(:chat, :fivesonly)
      @rollout.activate_user(:chat, double(id: 51))
      @rollout.activate_percentage(:chat, 100)
      @rollout.activate(:chat)
      @rollout.deactivate(:chat)
    end

    it "removes all of the groups" do
      expect(@rollout).not_to be_active(:chat, double(id: 0))
    end

    it "removes all of the users" do
      expect(@rollout).not_to be_active(:chat, double(id: 51))
    end

    it "removes the percentage" do
      expect(@rollout).not_to be_active(:chat, double(id: 24))
    end

    it "removes globally" do
      expect(@rollout).not_to be_active(:chat)
    end
  end

  describe "activating a specific user" do
    before do
      @rollout.activate_user(:chat, double(id: 42))
    end

    it "is active for that user" do
      expect(@rollout).to be_active(:chat, double(id: 42))
    end

    it "remains inactive for other users" do
      expect(@rollout).not_to be_active(:chat, double(id: 24))
    end
  end

  describe "activating a specific user by ID" do
    before do
      @rollout.activate_user(:chat, 42)
    end

    it "is active for that user" do
      expect(@rollout).to be_active(:chat, double(id: 42))
    end

    it "remains inactive for other users" do
      expect(@rollout).not_to be_active(:chat, double(id: 24))
    end
  end

  describe "activating a specific user with a string id" do
    before do
      @rollout.activate_user(:chat, double(id: "user-72"))
    end

    it "is active for that user" do
      expect(@rollout).to be_active(:chat, double(id: "user-72"))
    end

    it "remains inactive for other users" do
      expect(@rollout).not_to be_active(:chat, double(id: "user-12"))
    end
  end

  describe "activating a group of users" do
    context "specified by user objects" do
      let(:users) { [double(id: 1), double(id: 2), double(id: 3)] }

      before { @rollout.activate_users(:chat, users) }

      it "is active for the given users" do
        users.each { |user| expect(@rollout).to be_active(:chat, user) }
      end

      it "remains inactive for other users" do
        expect(@rollout).not_to be_active(:chat, double(id: 4))
      end
    end

    context "specified by user ids" do
      let(:users) { [1, 2, 3] }

      before { @rollout.activate_users(:chat, users) }

      it "is active for the given users" do
        users.each { |user| expect(@rollout).to be_active(:chat, user) }
      end

      it "remains inactive for other users" do
        expect(@rollout).not_to be_active(:chat, 4)
      end
    end
  end

  describe "deactivating a specific user" do
    before do
      @rollout.activate_user(:chat, double(id: 42))
      @rollout.activate_user(:chat, double(id: 4242))
      @rollout.activate_user(:chat, double(id: 24))
      @rollout.deactivate_user(:chat, double(id: 42))
      @rollout.deactivate_user(:chat, double(id: "4242"))
    end

    it "that user should no longer be active" do
      expect(@rollout).not_to be_active(:chat, double(id: 42))
    end

    it "remains active for other active users" do
      @options = @rollout.instance_variable_get("@options")
      @options[:use_sets] = false
      expect(@rollout.get(:chat).users).to eq %w(24)
    end

    it "remains active for other active users using sets" do
      @options = @rollout.instance_variable_get("@options")
      @options[:use_sets] = true

      expect(@rollout.get(:chat).users).to eq %w(24).to_set
    end
  end

  describe "deactivating a group of users" do
    context "specified by user objects" do
      let(:active_users) { [double(id: 1), double(id: 2)] }
      let(:inactive_users) { [double(id: 3), double(id: 4)] }

      before do
        @rollout.activate_users(:chat, active_users + inactive_users)
        @rollout.deactivate_users(:chat, inactive_users)
      end

      it "is active for the active users" do
        active_users.each { |user| expect(@rollout).to be_active(:chat, user) }
      end

      it "is not active for inactive users" do
        inactive_users.each { |user| expect(@rollout).not_to be_active(:chat, user) }
      end
    end

    context "specified by user ids" do
      let(:active_users) { [1, 2] }
      let(:inactive_users) { [3, 4] }

      before do
        @rollout.activate_users(:chat, active_users + inactive_users)
        @rollout.deactivate_users(:chat, inactive_users)
      end

      it "is active for the active users" do
        active_users.each { |user| expect(@rollout).to be_active(:chat, user) }
      end

      it "is not active for inactive users" do
        inactive_users.each { |user| expect(@rollout).not_to be_active(:chat, user) }
      end
    end
  end


  describe 'set a group of users' do
    it 'should replace the users with the given array' do
      users = %w(1 2 3 4)
      @rollout.activate_users(:chat, %w(10 20 30))
      @rollout.set_users(:chat, users)
      expect(@rollout.get(:chat).users).to eq(users)
    end
  end

  describe "activating a feature globally" do
    before do
      @rollout.activate(:chat)
    end

    it "activates the feature" do
      expect(@rollout).to be_active(:chat)
    end

    it "sets @data to empty hash" do
      expect(@rollout.get(:chat).data).to eq({})
    end
  end

  describe "activating a feature for a percentage of users" do
    before do
      @rollout.activate_percentage(:chat, 20)
    end

    it "activates the feature for that percentage of the users" do
      expect((1..100).select { |id| @rollout.active?(:chat, double(id: id)) }.length).to be_within(2).of(20)
    end
  end

  describe "activating a feature for a percentage of users" do
    before do
      @rollout.activate_percentage(:chat, 20)
    end

    it "activates the feature for that percentage of the users" do
      expect((1..200).select { |id| @rollout.active?(:chat, double(id: id)) }.length).to be_within(4).of(40)
    end
  end

  describe "activating a feature for a percentage of users" do
    before do
      @rollout.activate_percentage(:chat, 5)
    end

    it "activates the feature for that percentage of the users" do
      expect((1..100).select { |id| @rollout.active?(:chat, double(id: id)) }.length).to be_within(2).of(5)
    end
  end

  describe "activating a feature for a percentage of users" do
    before do
      @rollout.activate_percentage(:chat, 0.1)
    end

    it "activates the feature for that percentage of the users" do
      expect((1..10_000).to_set.select { |id| @rollout.active?(:chat, double(id: id)) }.length).to be_within(2).of(10)
    end
  end

  describe "activating a feature for a percentage of users" do
    before do
      @rollout.activate_percentage(:chat, 20)
      @rollout.activate_percentage(:beta, 20)
      @options = @rollout.instance_variable_get("@options")
    end

    it "activates the feature for a random set of users when opt is set" do
      @options[:randomize_percentage] = true
      chat_users = (1..100).select { |id| @rollout.active?(:chat, double(id: id)) }
      beta_users = (1..100).select { |id| @rollout.active?(:beta, double(id: id)) }
      expect(chat_users).not_to eq beta_users
    end
    it "activates the feature for the same set of users when opt is not set" do
      @options[:randomize_percentage] = false
      chat_users = (1..100).select { |id| @rollout.active?(:chat, double(id: id)) }
      beta_users = (1..100).select { |id| @rollout.active?(:beta, double(id: id)) }
      expect(chat_users).to eq beta_users
    end
  end

  describe "activating a feature for a group as a string" do
    before do
      @rollout.define_group(:admins) { |user| user.id == 5 }
      @rollout.activate_group(:chat, "admins")
    end

    it "the feature is active for users for which the block evaluates to true" do
      expect(@rollout).to be_active(:chat, double(id: 5))
    end

    it "is not active for users for which the block evaluates to false" do
      expect(@rollout).not_to be_active(:chat, double(id: 1))
    end
  end

  describe "deactivating the percentage of users" do
    before do
      @rollout.activate_percentage(:chat, 100)
      @rollout.deactivate_percentage(:chat)
    end

    it "becomes inactivate for all users" do
      expect(@rollout).not_to be_active(:chat, double(id: 24))
    end
  end

  describe "deactivating the feature globally" do
    before do
      @rollout.activate(:chat)
      @rollout.deactivate(:chat)
    end

    it "becomes inactivate" do
      expect(@rollout).not_to be_active(:chat)
    end
  end

  describe "setting a feature on" do
    before do
      @rollout.set(:chat, true)
    end

    it "becomes activated" do
      expect(@rollout).to be_active(:chat)
    end
  end

  describe "setting a feature off" do
    before do
      @rollout.set(:chat, false)
    end

    it "becomes inactivated" do
      expect(@rollout).not_to be_active(:chat)
    end
  end

  describe "deleting a feature" do
    before do
      @rollout.set(:chat, true)
    end

    context "when feature was passed as string" do
      it "should be removed from features list" do
        expect(@rollout.features.size).to eq 1
        @rollout.delete('chat')
        expect(@rollout.features.size).to eq 0
      end
    end

    it "should be removed from features list" do
      expect(@rollout.features.size).to eq 1
      @rollout.delete(:chat)
      expect(@rollout.features.size).to eq 0
    end

    it "should have metadata cleared" do
      expect(@rollout.get(:chat).percentage).to eq 100
      @rollout.delete(:chat)
      expect(@rollout.get(:chat).percentage).to eq 0
    end
  end

  describe "keeps a list of features" do
    it "saves the feature" do
      @rollout.activate(:chat)
      expect(@rollout.features).to be_include(:chat)
    end

    it "does not contain doubles" do
      @rollout.activate(:chat)
      @rollout.activate(:chat)
      expect(@rollout.features.size).to eq(1)
    end

    it "does not contain doubles when using string" do
      @rollout.activate(:chat)
      @rollout.activate("chat")
      expect(@rollout.features.size).to eq(1)
    end
  end

  describe "indexes all related fields of feature" do
    let(:user)     { double(id: 42) }
    let(:features) { %i(chat blog) }

    context "when users was changed" do
      before do
        features.each do |feature|
          @rollout.activate_user(feature, user)
        end
      end

      it "adds the new feature to the user index" do
        @rollout.activate_user(:video, user)
        index_key = @rollout.send("field_index", "users:#{user.id}")
        expect(@redis.sismember(index_key, :video)).to be_truthy
      end

      it "removes the new feature from the user index" do
        @rollout.deactivate_user(features[0], user)
        index_key = @rollout.send("field_index", "users:#{user.id}")
        expect(@redis.sismember(index_key, features[0])).to be_falsey
      end
    end

    context "when groups was changed" do
      let(:group) { :caretakers }

      before do
        features.each do |feature|
          @rollout.activate_group(feature, group)
        end
      end

      it "adds the new group to the group index" do
        @rollout.activate_group(:video, group)
        index_key = @rollout.send("field_index", "groups:#{group}")
        expect(@redis.sismember(index_key, :video)).to be_truthy
      end

      it "removes the group from the group index" do
        @rollout.deactivate_group(features[0], group)
        index_key = @rollout.send("field_index", "groups:#{group}")
        expect(@redis.sismember(index_key, features[0])).to be_falsey
      end
    end

    context "when percentage was changed" do
      let(:feature) { :blog }
      let(:percentage_key_100) { @rollout.send("percentage_field_index", 100) }
      let(:percentage_key_normal) { @rollout.send("percentage_field_index") }

      context "when the percentage was 100" do
        before do
          @rollout.activate_percentage(feature, 100) 
        end

        it "set the feature into 100 percentage index" do
          expect(@redis.sismember(percentage_key_100, feature)).to be_truthy
        end

        context "when changed the percentage to 85" do
          it "moves the feature to the normal percentage index" do
            @rollout.activate_percentage(feature, 85) 
            expect(@redis.sismember(percentage_key_100, feature)).to be_falsy
            expect(@redis.sismember(percentage_key_normal, feature)).to be_truthy
          end
        end

        context "when changed the percentage to 0" do
          it "removes the feature from all percentage index" do
            @rollout.activate_percentage(feature, 0) 
            expect(@redis.sismember(percentage_key_100, feature)).to be_falsy
            expect(@redis.sismember(percentage_key_normal, feature)).to be_falsy
          end
        end
      end

      context "when the percentage was 85" do
        before do
          @rollout.activate_percentage(feature, 85) 
        end

        it "set the feature into normal percentage index" do
          expect(@redis.sismember(percentage_key_normal, feature)).to be_truthy
        end

        context "when changed the percentage to 95" do
          it "moves the feature to the normal percentage index" do
            @rollout.activate_percentage(feature, 95) 
            expect(@redis.sismember(percentage_key_100, feature)).to be_falsy
            expect(@redis.sismember(percentage_key_normal, feature)).to be_truthy
          end
        end

        context "when changed the percentage to 100" do
          it "removes the feature from all percentage index" do
            @rollout.activate_percentage(feature, 100) 
            expect(@redis.sismember(percentage_key_100, feature)).to be_truthy
            expect(@redis.sismember(percentage_key_normal, feature)).to be_falsy
          end
        end

        context "when changed the percentage to 0" do
          it "removes the feature from all percentage index" do
            @rollout.activate_percentage(feature, 0) 
            expect(@redis.sismember(percentage_key_100, feature)).to be_falsy
            expect(@redis.sismember(percentage_key_normal, feature)).to be_falsy
          end
        end
      end

      context "when the feature was deleted" do
        before do
          @rollout.activate_group(feature, :alpha)
          @rollout.activate_percentage(feature, 10)
          @rollout.activate_user(feature, user)
        end

        it "empty all of indices" do
          @rollout.delete(feature)
          expect(@redis.exists(@rollout.send("field_index", "users:#{user.id}"))).to be_falsey
          expect(@redis.exists(@rollout.send("field_index", "groups:alpha"))).to be_falsey
          expect(@redis.exists(@rollout.send("field_index", @rollout.send("percentage_field_index")))).to be_falsey
        end
      end

      context "when features created by earlier version" do
        let(:group)           { :reindexed_group }
        let(:grouped_feature) { :grouped_feature }
        let(:global_feature)  { :feature_100_percent }

        before do
          allow(@rollout).to receive(:reindex).and_return(nil)
          @rollout.define_group(group) do |user|
            user.id == 42
          end

          features.each do |feature|
            @rollout.activate_user(feature, user)
          end
          @rollout.activate_group(grouped_feature, group)
          @rollout.activate_percentage(global_feature, 100)
        end

        it "reindex all of features" do
          @rollout.reindex_all
          expect(@rollout.active_features(user)).to contain_exactly(*features, grouped_feature, global_feature)
        end
      end
    end
  end

  describe "#get" do
    before do
      @rollout.activate_percentage(:chat, 10)
      @rollout.activate_group(:chat, :caretakers)
      @rollout.activate_group(:chat, :greeters)
      @rollout.activate(:signup)
      @rollout.activate_user(:chat, double(id: 42))
    end

    it "returns the feature object" do
      feature = @rollout.get(:chat)
      expect(feature.groups).to eq [:caretakers, :greeters]
      expect(feature.percentage).to eq 10
      expect(feature.users).to eq %w(42)
      expect(feature.to_hash).to eq(
        groups: [:caretakers, :greeters],
        percentage: 10,
        users: %w(42)
      )

      feature = @rollout.get(:signup)
      expect(feature.groups).to be_empty
      expect(feature.users).to be_empty
      expect(feature.percentage).to eq(100)
    end

    it "returns the feature objects using sets" do
      @options = @rollout.instance_variable_get("@options")
      @options[:use_sets] = true

      feature = @rollout.get(:chat)
      expect(feature.groups).to eq [:caretakers, :greeters].to_set
      expect(feature.percentage).to eq 10
      expect(feature.users).to eq %w(42).to_set
      expect(feature.to_hash).to eq(
        groups: [:caretakers, :greeters].to_set,
        percentage: 10,
        users: %w(42).to_set
      )

      feature = @rollout.get(:signup)
      expect(feature.groups).to be_empty
      expect(feature.users).to be_empty
      expect(feature.percentage).to eq(100)
    end
  end

  describe "#clear" do
    let(:features) { %w(signup beta alpha gm) }

    before do
      features.each { |f| @rollout.activate(f) }

      @rollout.clear!
    end

    it "each feature is cleared" do
      features.each do |feature|
        expect(@rollout.get(feature).to_hash).to eq(
          percentage: 0,
          users: [],
          groups: []
        )
      end
    end

    it "each feature is cleared with sets" do
      @options = @rollout.instance_variable_get("@options")
      @options[:use_sets] = true
      features.each do |feature|
        expect(@rollout.get(feature).to_hash).to eq(
          percentage: 0,
          users: Set.new,
          groups: Set.new
        )
      end
    end

    it "removes all features" do
      expect(@rollout.features).to be_empty
    end
  end

  describe "#feature_states" do
    let(:user_double) { double(id: 7) }

    before do
      @rollout.activate(:chat)
      @rollout.activate_user(:video, user_double)
      @rollout.deactivate(:vr)
    end

    it "returns a hash" do
      expect(@rollout.feature_states).to be_a(Hash)
    end

    context "with user argument" do
      it "maps active feature as true" do
        state = @rollout.feature_states(user_double)[:video]
        expect(state).to eq(true)
      end

      it "maps inactive feature as false" do
        state = @rollout.feature_states[:vr]
        expect(state).to eq(false)
      end
    end

    context "with no argument" do
      it "maps active feature as true" do
        state = @rollout.feature_states[:chat]
        expect(state).to eq(true)
      end

      it "maps inactive feature as false" do
        state = @rollout.feature_states[:video]
        expect(state).to eq(false)
      end
    end
  end

  describe "#active_features" do
    let(:user_double) { double(id: 19) }

    before do
      @rollout.activate(:chat)
      @rollout.activate_user(:video, user_double)
      @rollout.deactivate(:vr)
    end

    it "returns an array" do
      expect(@rollout.active_features).to be_a(Array)
    end

    context "with user argument" do
      it "includes active feature" do
        features = @rollout.active_features(user_double)
        expect(features).to include(:video)
        expect(features).to include(:chat)
      end

      it "excludes inactive feature" do
        features = @rollout.active_features(user_double)
        expect(features).to_not include(:vr)
      end
    end

    context "with no argument" do
      it "includes active feature" do
        features = @rollout.active_features
        expect(features).to include(:chat)
      end

      it "excludes inactive feature" do
        features = @rollout.active_features
        expect(features).to_not include(:video)
      end
    end
  end

  describe "#groups_user_belongs_to" do
    let(:user) { double(id: 5, level: 4) }
    before do
      @rollout.define_group(:alpha) { |user| user.level > 5 }
      @rollout.define_group(:beta) { |user| user.level > 3 }
      @rollout.define_group(:gama) { |user| user.level > 1 }
    end

    it "returns an array conatins groups the user blogns to" do
      expect(@rollout.groups_user_belongs_to(user)).to match_array([:all, :beta, :gama])
    end
  end

  describe "#user_in_active_users?" do
    it "returns true if activated for user" do
      @rollout.activate_user(:chat, double(id: 5))
      expect(@rollout.user_in_active_users?(:chat, "5")).to eq(true)
    end

    it "returns false if activated for group" do
      @rollout.activate_group(:chat, :all)
      expect(@rollout.user_in_active_users?(:chat, "5")).to eq(false)
    end
  end

  describe "#multi_get" do
    before do
      @rollout.activate_percentage(:chat, 10)
      @rollout.activate_group(:chat, :caretakers)
      @rollout.activate_group(:videos, :greeters)
      @rollout.activate(:signup)
      @rollout.activate_user(:photos, double(id: 42))
    end

    it "returns an array of features" do
      features = @rollout.multi_get(:chat, :videos, :signup)
      expect(features[0].name).to eq :chat
      expect(features[0].groups).to eq [:caretakers]
      expect(features[0].percentage).to eq 10
      expect(features[1].name).to eq :videos
      expect(features[1].groups).to eq [:greeters]
      expect(features[2].name).to eq :signup
      expect(features[2].percentage).to eq 100
      expect(features.size).to eq 3
    end

    describe 'when given feature keys is empty' do
      it 'returns empty array' do
        expect(@rollout.multi_get(*[])).to match_array([])
      end
    end
  end

  describe "#set_feature_data" do
    before do
      @rollout.set_feature_data(:chat, description: 'foo', release_date: 'bar')
    end

    it 'sets the data attribute on feature' do
      expect(@rollout.get(:chat).data).to include('description' => 'foo', 'release_date' => 'bar')
    end

    it 'updates a data attribute' do
      @rollout.set_feature_data(:chat, description: 'baz')
      expect(@rollout.get(:chat).data).to include('description' => 'baz', 'release_date' => 'bar')
    end

    it 'only sets data on specified feature' do
      @rollout.set_feature_data(:talk, image_url: 'kittens.png')
      expect(@rollout.get(:chat).data).not_to include('image_url' => 'kittens.png')
      expect(@rollout.get(:chat).data).to include('description' => 'foo', 'release_date' => 'bar')
    end

    it 'does not modify @data if param is nil' do
      expect(@rollout.get(:chat).data).to include('description' => 'foo', 'release_date' => 'bar')
      @rollout.set_feature_data(:chat, nil)
      expect(@rollout.get(:chat).data).to include('description' => 'foo', 'release_date' => 'bar')
    end

    it 'does not modify @data if param is empty string' do
      expect(@rollout.get(:chat).data).to include('description' => 'foo', 'release_date' => 'bar')
      @rollout.set_feature_data(:chat, "   ")
      expect(@rollout.get(:chat).data).to include('description' => 'foo', 'release_date' => 'bar')
    end

    it 'properly parses data when it contains a |' do
      user = double("User", id: 8)
      @rollout.activate_user(:chat, user)
      @rollout.set_feature_data(:chat, "|call||text|" => "a|bunch|of|stuff")
      expect(@rollout.get(:chat).data).to include("|call||text|" => "a|bunch|of|stuff")
      expect(@rollout.active?(:chat, user)).to be true
    end
  end

  describe "#user_id" do
    let(:user) { double(id: "12", email: "test@test.com") }

    it "returns a string" do
      expect(Rollout.user_id(123)).to be_a(String) 
    end

    it "extracts the id attribute as user id" do
      expect(Rollout.user_id(user)).to be(user.id) 
    end

    it "extracts the specific attribute as user id" do
      expect(Rollout.user_id(user, "email")).to be(user.email) 
    end
  end

  describe "#clear_feature_data" do
    it 'resets data to empty string' do
      @rollout.set_feature_data(:chat, description: 'foo')
      expect(@rollout.get(:chat).data).to include('description' => 'foo')
      @rollout.clear_feature_data(:chat)
      expect(@rollout.get(:chat).data).to eq({})
    end
  end

  describe 'Check if feature exists' do
    it 'it should return true if the feature is exist' do
      @rollout.activate_percentage(:chat, 1)
      expect(@rollout.exists?(:chat)).to be true
    end

    it 'it should return false if the feature is not exist' do
      expect(@rollout.exists?(:chat)).to be false
    end
  end
end

describe "Rollout::Feature" do
  describe "#add_user" do
    it "ids a user using id_user_by" do
      user    = double("User", email: "test@test.com")
      feature = Rollout::Feature.new(:chat, nil, id_user_by: :email)
      feature.add_user(user)
      expect(user).to have_received :email
    end
  end

  describe "#initialize" do
    describe "when string does not exist" do
      it 'clears feature attributes when string is not given' do
        feature = Rollout::Feature.new(:chat)
        expect(feature.groups).to be_empty
        expect(feature.users).to be_empty
        expect(feature.percentage).to eq 0
        expect(feature.data).to eq({})
      end

      it 'clears feature attributes when string is nil' do
        feature = Rollout::Feature.new(:chat, nil)
        expect(feature.groups).to be_empty
        expect(feature.users).to be_empty
        expect(feature.percentage).to eq 0
        expect(feature.data).to eq({})
      end

      it 'clears feature attributes when string is empty string' do
        feature = Rollout::Feature.new(:chat, "")
        expect(feature.groups).to be_empty
        expect(feature.users).to be_empty
        expect(feature.percentage).to eq 0
        expect(feature.data).to eq({})
      end

      describe "when there is no data" do
        it 'sets @data to empty hash' do
          feature = Rollout::Feature.new(:chat, "0||")
          expect(feature.data).to eq({})
        end

        it 'sets @data to empty hash' do
          feature = Rollout::Feature.new(:chat, "|||   ")
          expect(feature.data).to eq({})
        end
      end
    end
  end
end
