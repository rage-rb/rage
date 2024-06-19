module ParametersWrappers
  class ParametersWrapper
    def initialize(wrapper_key, options)
      @wrapper_key = wrapper_key
      @options = options
    end

    def wrap_params(params)
      params.merge(wrapper_key => filtered_params(params))
    end

    private

    attr_reader :wrapper_key, :options

    def filtered_params(params)
      if options[:include]
        params.slice(*[options[:include]].flatten)
      elsif options[:exclude]
        params.except(*[options[:exclude]].flatten)
      end
    end
  end
end
