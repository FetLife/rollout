require "rollout/legacy"
require "zlib"
require 'ipaddress'

class Rollout
  class Feature
    attr_reader :name, :groups, :users, :percentage, :ips
    attr_writer :percentage, :groups, :users, :ips

    def initialize(name, string = nil)
      @name = name
      if string
        raw_percentage,raw_users,raw_groups,raw_ips = string.split("|")
        @percentage = raw_percentage.to_i
        @users = (raw_users || "").split(",").map(&:to_s)
        @groups = (raw_groups || "").split(",").map(&:to_sym)
        @ips = (raw_ips || "").split(",").map(&:to_s)
      else
        clear
      end
    end

    def serialize
      "#{@percentage}|#{@users.join(",")}|#{@groups.join(",")}|#{@ips.join(",")}"
    end

    def add_user(user)
      @users << user.id.to_s unless @users.include?(user.id.to_s)
    end

    def remove_user(user)
      @users.delete(user.id.to_s)
    end

    def add_group(group)
      @groups << group.to_sym unless @groups.include?(group.to_sym)
    end

    def remove_group(group)
      @groups.delete(group.to_sym)
    end

    def add_ip(ip)
      begin 
        if IPAddress.valid? ip
          @ips << ip.to_sym unless @ips.include?(ip.to_s)
        end
      rescue
      end
    end

    def remove_ip(ip)
      @ips.delete(ip.to_sym)
    end



    def clear
      @groups = []
      @users = []
      @percentage = 0
      @ips = []
    end

    def active?(rollout, user)
      if user.nil?
        @percentage == 100
      else
        user_in_percentage?(user) ||
          user_in_active_users?(user) ||
            user_in_active_group?(user, rollout)
      end
    end

    def active_ip?(rollout, ip)
      if ip.nil?
        @percentage == 100
      else
        ip_in_percentage?(ip) ||
          ip_in_active_ips?(ip) 
      end
    end

    def to_hash
      {:percentage => @percentage,
       :groups     => @groups,
       :users      => @users,
       :ips        => @ips
     }
    end

    private
      def user_in_percentage?(user)
        Zlib.crc32(user.id.to_s) % 100 < @percentage
      end

      def user_in_active_users?(user)
        @users.include?(user.id.to_s)
      end

      def ip_in_percentage?(ip)
        ip.split('.').inject(0) {|total,value| (total << 8 ) + value.to_i} % 100 < @percentage
      end

      def ip_in_active_ips?(ip)
        @ips.include?(ip.to_s)
      end


      def user_in_active_group?(user, rollout)
        @groups.any? do |g|
          rollout.active_in_group?(g, user)
        end
      end
  end

  def initialize(storage, opts = {})
    @storage  = storage
    @groups = {:all => lambda { |user| true }}
    @legacy = Legacy.new(opts[:legacy_storage] || @storage) if opts[:migrate]
  end

  def activate(feature)
    with_feature(feature) do |f|
      f.percentage = 100
    end
  end

  def deactivate(feature)
    with_feature(feature) do |f|
      f.clear
    end
  end

  def activate_group(feature, group)
    with_feature(feature) do |f|
      f.add_group(group)
    end
  end

  def deactivate_group(feature, group)
    with_feature(feature) do |f|
      f.remove_group(group)
    end
  end

  def activate_ip(feature, ip)
    with_feature(feature) do |f|
      f.add_ip(ip)
    end
  end

  def deactivate_ip(feature, ip)
    with_feature(feature) do |f|
      f.remove_ip(ip)
    end
  end

  def activate_user(feature, user)
    with_feature(feature) do |f|
      f.add_user(user)
    end
  end

  def deactivate_user(feature, user)
    with_feature(feature) do |f|
      f.remove_user(user)
    end
  end

  def define_group(group, &block)
    @groups[group.to_sym] = block
  end

  def active?(feature, user = nil)
    feature = get(feature)
    feature.active?(self, user)
  end

  def active_ip?(feature, ip = nil)
    feature = get(feature)
    feature.active_ip?(self, ip)
  end

  def activate_percentage(feature, percentage)
    with_feature(feature) do |f|
      f.percentage = percentage
    end
  end

  def deactivate_percentage(feature)
    with_feature(feature) do |f|
      f.percentage = 0
    end
  end

  def active_in_group?(group, user)
    f = @groups[group.to_sym]
    f && f.call(user)
  end

  def get(feature)
    string = @storage.get(key(feature))
    if string || !migrate?
      Feature.new(feature, string)
    else
      info = @legacy.info(feature)
      f = Feature.new(feature)
      f.percentage = info[:percentage]
      f.groups = info[:groups].map { |g| g.to_sym }
      f.users = info[:users].map { |u| u.to_s }
      save(f)
      f
    end
  end

  def features
    (@storage.get(features_key) || "").split(",").map(&:to_sym)
  end

  private
    def key(name)
      "feature:#{name}"
    end

    def features_key
      "feature:__features__"
    end

    def with_feature(feature)
      f = get(feature)
      yield(f)
      save(f)
    end

    def save(feature)
      @storage.set(key(feature.name), feature.serialize)
      @storage.set(features_key, (features | [feature.name]).join(","))
    end

    def migrate?
      @legacy
    end
end
