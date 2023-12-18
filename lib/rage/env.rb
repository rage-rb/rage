# frozen_string_literal: true

class Rage::Env
  STANDARD_ENVS = %w(development test staging production)

  def initialize(env)
    @env = env

    STANDARD_ENVS.each do |standard_env|
      self.class.define_method("#{standard_env}?") { false } if standard_env != @env
    end
    self.class.define_method("#{@env}?") { true }
  end

  def method_missing(method_name, *, &)
    method_name.end_with?("?") ? false : super
  end

  def respond_to_missing?(method_name, include_private = false)
    method_name.end_with?("?")
  end

  def ==(other)
    @env == other
  end

  def to_sym
    @env.to_sym
  end

  def to_s
    @env
  end
end
