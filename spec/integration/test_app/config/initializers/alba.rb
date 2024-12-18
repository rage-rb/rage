module TestInflector
  module_function

  def camelize(_)
  end

  def camelize_lower(_)
  end

  def dasherize(_)
  end

  def underscore(_)
  end

  def classify(string)
    case string.to_s
    when "avatar"
      "Avatar"
    when "comments"
      "Comment"
    end
  end
end

Alba.inflector = TestInflector
