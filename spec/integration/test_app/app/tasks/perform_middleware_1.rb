class PerformMiddleware1
  def call(task_class:, context:)
    return yield unless task_class == CreateFile

    context[:middleware] << self.class.name
    yield
  end
end
