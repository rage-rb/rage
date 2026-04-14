class EnqueueMiddleware1
  def call(task_class:, args:, context:)
    return yield unless task_class == CreateFile

    args << "w"
    context[:middleware] = [self.class.name]
    yield
  end
end
