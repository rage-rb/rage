class PerformMiddleware2
  def call(task_class:, kwargs:, context:)
    return yield unless task_class == CreateFile

    context[:middleware] << self.class.name
    kwargs[:content] = context[:middleware].join("->")
    yield
  end
end
