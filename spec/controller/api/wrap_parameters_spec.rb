RSpec.describe RageController::API do
  describe 'parameters wrapping logic' do
    context 'when parameters wrapper is not declared' do
      let(:controller) do
        Class.new(RageController::API) do
          def index
            render json: params
          end
        end
      end

      it "doesn't wrap the parameters" do
        initial_params = {param: :value}
        expected_result = {param: :value}

        response = run_action(controller, :index, params: initial_params, env: {'CONTENT_TYPE' => "application/json"})
        expect(response).to match([200, instance_of(Hash), [expected_result.to_json]])
      end
    end

    context 'when parameters wrapper is declared without options' do
      let(:controller) do
        Class.new(RageController::API) do
          wrap_parameters :root

          def index
            render json: params
          end
        end
      end

      context "and wrapping root doesn't conflict with parameter key" do
        context 'and CONTENT_TYPE header is blank' do
          it "doesn't wrap the parameters into a nested hash" do
            initial_params = {param: :value}
            expected_result = {param: :value}

            response = run_action(controller, :index, params: initial_params)
            expect(response).to match([200, instance_of(Hash), [expected_result.to_json]])
          end
        end

        context 'and CONTENT_TYPE header is present' do
          it 'wraps the parameters into a nested hash without the reserved params' do
            initial_params = {param: :value, action: :action, controller: :controller}
            expected_result = {param: :value, action: :action, controller: :controller, root: {param: :value}}

            response = run_action(
              controller,
              :index,
              params: initial_params,
              env: {'CONTENT_TYPE' => "application/json"}
            )

            expect(response).to match([200, instance_of(Hash), [expected_result.to_json]])
          end
        end
      end

      context 'and wrapping root conflicts with parameter key' do
        it "doesn't wrap the parameters into a nested hash" do
          initial_params = {root: :value, param: :value, action: :action, controller: :controller}
          expected_result = {root: :value, param: :value, action: :action, controller: :controller}

          response = run_action(controller, :index, params: initial_params, env: {'CONTENT_TYPE' => "application/json"})
          expect(response).to match([200, instance_of(Hash), [expected_result.to_json]])
        end
      end
    end

    context 'when parameters wrapper is declared with :include option' do
      let(:controller) do
        Class.new(RageController::API) do
          wrap_parameters :root, include: %i[param_a param_b]

          def index
            render json: params
          end
        end
      end

      context 'and params to include are present in request' do
        it 'wraps the params that are set to be included' do
          initial_params = {param_a: :value, param_b: :value, param_c: :value, action: :action, controller: :controller}
          expected_result = {
            param_a: :value,
            param_b: :value,
            param_c: :value,
            action: :action,
            controller: :controller,
            root: {param_a: :value, param_b: :value}
          }

          response = run_action(controller, :index, params: initial_params, env: {'CONTENT_TYPE' => "application/json"})
          expect(response).to match([200, instance_of(Hash), [expected_result.to_json]])
        end
      end

      context "and params to include aren't present in request" do
        it 'adds empty hash under wrapping key to params' do
          initial_params = {param_c: :value, action: :action, controller: :controller}
          expected_result = {param_c: :value, action: :action, controller: :controller, root: {}}

          response = run_action(controller, :index, params: initial_params, env: {'CONTENT_TYPE' => "application/json"})
          expect(response).to match([200, instance_of(Hash), [expected_result.to_json]])
        end
      end
    end

    context 'when parameters wrapper is declared with :exclude option' do
      let(:controller) do
        Class.new(RageController::API) do
          wrap_parameters :root, exclude: %i[param_a param_b]

          def index
            render json: params
          end
        end
      end

      context 'and params to exclude are present in request' do
        it 'wraps the params except those that are set to be excluded and those that need to be excluded by default' do
          initial_params = {param_a: :value, param_b: :value, param_c: :value, action: :action, controller: :controller}
          expected_result = {
            param_a: :value,
            param_b: :value,
            param_c: :value,
            action: :action,
            controller: :controller,
            root: {param_c: :value}
          }

          response = run_action(controller, :index, params: initial_params, env: {'CONTENT_TYPE' => "application/json"})
          expect(response).to match([200, instance_of(Hash), [expected_result.to_json]])
        end
      end

      context "and params to exclude aren't present in request" do
        it 'wraps the params except those that need to be excluded by default ' do
          initial_params = {param_c: :value, action: :action, controller: :controller}
          expected_result = {param_c: :value, action: :action, controller: :controller, root: {param_c: :value}}

          response = run_action(controller, :index, params: initial_params, env: {'CONTENT_TYPE' => "application/json"})
          expect(response).to match([200, instance_of(Hash), [expected_result.to_json]])
        end
      end
    end

    context 'when parameters wrapper is declared with both :exclude and :include options' do
      let(:controller) do
        Class.new(RageController::API) do
          wrap_parameters :root, exclude: %i[param_a], include: %i[param_a]

          def index
            render json: params
          end
        end
      end

      it 'wraps the params using the :include option' do
        initial_params = {param_a: :value, param_b: :value}
        expected_result = {param_a: :value, param_b: :value, root: {param_a: :value}}

        response = run_action(controller, :index, params: initial_params, env: {'CONTENT_TYPE' => "application/json"})
        expect(response).to match([200, instance_of(Hash), [expected_result.to_json]])
      end
    end

    context 'controller inheritance' do
      let(:grandchild_controller) do
        Class.new(child_controller) do
          def index
            render json: params
          end
        end
      end

      context 'when parameters wrapper is declared in parent controller' do
        let(:parent_controller) do
          Class.new(RageController::API) do
            wrap_parameters :parent_root, include: %i[parent_param]

            def index
              render json: params
            end
          end
        end

        context 'and parameters wrapper is declared in child controller' do
          context 'and child wrapper is declared without options' do
            let(:child_controller) do
              Class.new(parent_controller) do
                wrap_parameters :child_root

                def index
                  render json: params
                end
              end
            end

            let(:initial_params) { {parent_param: :value, child_param: :value} }
            let(:expected_result) do
              {
                parent_param: :value,
                child_param: :value,
                child_root: {parent_param: :value, child_param: :value}
              }
            end

            it 'wraps params of child controller using wrapping key of child controller without options' do
              response = run_action(
                child_controller,
                :index,
                params: initial_params,
                env: {'CONTENT_TYPE' => "application/json"}
              )

              expect(response).to match([200, instance_of(Hash), [expected_result.to_json]])
            end

            it 'wraps params of grandchild controller using wrapping key of child controller without options' do
              response = run_action(
                grandchild_controller,
                :index,
                params: initial_params,
                env: {'CONTENT_TYPE' => "application/json"}
              )

              expect(response).to match([200, instance_of(Hash), [expected_result.to_json]])
            end
          end

          context 'and child wrapper is defined with options' do
            let(:child_controller) do
              Class.new(parent_controller) do
                wrap_parameters :child_root, include: %i[child_param]

                def index
                  render json: params
                end
              end
            end

            let(:initial_params) { {parent_param: :value, child_param: :value} }
            let(:expected_result) { {parent_param: :value, child_param: :value, child_root: {child_param: :value}} }

            it 'wraps params of child controller using wrapping key and options of child controller' do
              response = run_action(
                child_controller,
                :index,
                params: initial_params,
                env: {'CONTENT_TYPE' => "application/json"}
              )

              expect(response).to match([200, instance_of(Hash), [expected_result.to_json]])
            end

            it 'wraps params of grandchild controller using wrapping key and options of child controller' do
              response = run_action(
                grandchild_controller,
                :index,
                params: initial_params,
                env: {'CONTENT_TYPE' => "application/json"}
              )

              expect(response).to match([200, instance_of(Hash), [expected_result.to_json]])
            end
          end
        end

        context 'and parameters wrapper is not declared in child controller' do
          let(:child_controller) do
            Class.new(parent_controller) do
              def index
                render json: params
              end
            end
          end

          let(:initial_params) { {parent_param: :value, child_param: :value} }
          let(:expected_result) { {parent_param: :value, child_param: :value, parent_root: {parent_param: :value}} }

          it 'wraps params of child controller using wrapping key and options of parent controller' do
            response = run_action(
              child_controller,
              :index,
              params: initial_params,
              env: {'CONTENT_TYPE' => "application/json"}
            )

            expect(response).to match([200, instance_of(Hash), [expected_result.to_json]])
          end

          it 'wraps params of grandchild controller using wrapping key and options of parent controller' do
            response = run_action(
              child_controller,
              :index,
              params: initial_params,
              env: {'CONTENT_TYPE' => "application/json"}
            )

            expect(response).to match([200, instance_of(Hash), [expected_result.to_json]])
          end
        end
      end
    end
  end
end
