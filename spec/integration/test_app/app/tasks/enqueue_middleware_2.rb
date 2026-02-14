class EnqueueMiddleware2
  def call(context:)
    context[:middleware] << self.class.name
    yield
  end
end
