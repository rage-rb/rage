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

        expect(run_action(controller, :index, params: initial_params)).to match(
          [200, instance_of(Hash), [expected_result.to_json]]
        )
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
        it 'wraps the parameters into a nested hash' do
          initial_params = {param: :value}
          expected_result = {param: :value, root: {param: :value}}

          expect(run_action(controller, :index, params: initial_params)).to match(
            [200, instance_of(Hash), [expected_result.to_json]]
          )
        end
      end

      context 'and wrapping root conflicts with parameter key' do
        it 'wraps the parameters into a nested hash and overrides the conflicting key' do
          initial_params = {root: :value, param: :value}
          expected_result = {root: {root: :value, param: :value}, param: :value}

          expect(run_action(controller, :index, params: initial_params)).to match(
            [200, instance_of(Hash), [expected_result.to_json]]
          )
        end
      end
    end

    context 'when parameters wrapper is declared with :include option' do
      context 'and :include option is set as Symbol' do
        let(:controller) do
          Class.new(RageController::API) do
            wrap_parameters :root, include: :param_a

            def index
              render json: params
            end
          end
        end

        it 'wraps the param that is set to be included' do
          initial_params = {param_a: :value, param_b: :value}
          expected_result = {param_a: :value, param_b: :value, root: {param_a: :value}}

          expect(run_action(controller, :index, params: initial_params)).to match(
            [200, instance_of(Hash), [expected_result.to_json]]
          )
        end
      end

      context 'and :include option is set as Array' do
        let(:controller) do
          Class.new(RageController::API) do
            wrap_parameters :root, include: [:param_a, :param_b]

            def index
              render json: params
            end
          end
        end

        it 'wraps the params that are set to be included' do
          initial_params = {param_a: :value, param_b: :value, param_c: :value}
          expected_result = {
            param_a: :value,
            param_b: :value,
            param_c: :value,
            root: {param_a: :value, param_b: :value}
          }

          expect(run_action(controller, :index, params: initial_params)).to match(
            [200, instance_of(Hash), [expected_result.to_json]]
          )
        end
      end
    end

    context 'when parameters wrapper is declared with :exclude option' do
      context 'and :exclude option is set as Symbol' do
        let(:controller) do
          Class.new(RageController::API) do
            wrap_parameters :root, exclude: :param_a

            def index
              render json: params
            end
          end
        end

        it 'wraps the params except the param that is set to be excluded' do
          initial_params = {param_a: :value, param_b: :value}
          expected_result = {param_a: :value, param_b: :value, root: {param_b: :value}}

          expect(run_action(controller, :index, params: initial_params)).to match(
            [200, instance_of(Hash), [expected_result.to_json]]
          )
        end
      end

      context 'and :exclude option is set as Array' do
        let(:controller) do
          Class.new(RageController::API) do
            wrap_parameters :root, exclude: [:param_a, :param_b]

            def index
              render json: params
            end
          end
        end

        it 'wraps the params except the params that are set to be excluded' do
          initial_params = {param_a: :value, param_b: :value, param_c: :value}
          expected_result = {param_a: :value, param_b: :value, param_c: :value, root: {param_c: :value}}

          expect(run_action(controller, :index, params: initial_params)).to match(
            [200, instance_of(Hash), [expected_result.to_json]]
          )
        end
      end
    end

    context 'when parameters wrapper is declared with both :exclude and :include options' do
      let(:controller) do
        Class.new(RageController::API) do
          wrap_parameters :root, exclude: :param_a, include: :param_a

          def index
            render json: params
          end
        end
      end

      it 'wraps the params using the :include option' do
        initial_params = {param_a: :value, param_b: :value}
        expected_result = {param_a: :value, param_b: :value, root: {param_a: :value}}

        expect(run_action(controller, :index, params: initial_params)).to match(
          [200, instance_of(Hash), [expected_result.to_json]]
        )
      end
    end
  end

  describe 'controller inheritance' do
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
          wrap_parameters :parent_root, include: [:parent_param]

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
            expect(run_action(child_controller, :index, params: initial_params)).to match(
              [200, instance_of(Hash), [expected_result.to_json]]
            )
          end

          it 'wraps params of grandchild controller using wrapping key of child controller without options' do
            expect(run_action(grandchild_controller, :index, params: initial_params)).to match(
              [200, instance_of(Hash), [expected_result.to_json]]
            )
          end
        end

        context 'and child wrapper is defined with options' do
          let(:child_controller) do
            Class.new(parent_controller) do
              wrap_parameters :child_root, include: [:child_param]

              def index
                render json: params
              end
            end
          end

          let(:initial_params) { {parent_param: :value, child_param: :value} }
          let(:expected_result) { {parent_param: :value, child_param: :value, child_root: {child_param: :value}} }

          it 'wraps params of child controller using wrapping key and options of child controller' do
            expect(run_action(child_controller, :index, params: initial_params)).to match(
              [200, instance_of(Hash), [expected_result.to_json]]
            )
          end

          it 'wraps params of grandchild controller using wrapping key and options of child controller' do
            expect(run_action(grandchild_controller, :index, params: initial_params)).to match(
              [200, instance_of(Hash), [expected_result.to_json]]
            )
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
          expect(run_action(child_controller, :index, params: initial_params)).to match(
           [200, instance_of(Hash), [expected_result.to_json]]
         )
        end

        it 'wraps params of grandchild controller using wrapping key and options of parent controller' do
          expect(run_action(child_controller, :index, params: initial_params)).to match(
            [200, instance_of(Hash), [expected_result.to_json]]
          )
        end
      end
    end
  end
end
