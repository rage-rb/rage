class EnqueueMiddleware1
  def call(args:, context:)
    args << "w"
    context[:middleware] = [self.class.name]
    yield
  end
end
