class PerformMiddleware1
  def call(context:)
    context[:middleware] << self.class.name
    yield
  end
end
