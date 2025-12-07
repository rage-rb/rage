class PerformMiddleware2
  def call(kwargs:, context:)
    context[:middleware] << self.class.name
    kwargs[:content] = context[:middleware].join("->")
    yield
  end
end
