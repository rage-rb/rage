# frozen_string_literal: true

require "blueprinter"
require "active_support/inflector"

RSpec.describe Rage::OpenAPI::Parsers::Ext::Blueprinter do
  include_context "mocked_classes"

  subject { described_class.new(**options).parse(resource) }

  let(:options) { {} }

  describe "single object" do
    let(:resource) { "UserBlueprint" }

    context "with an empty blueprint" do
      let_blueprinter_class("UserBlueprint") do
        <<~'RUBY'
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object" })
      end
    end

    context "with basic fields" do
      let_blueprinter_class("UserBlueprint") do
        <<~'RUBY'
          fields :id, :name, :email, :age
        RUBY
      end
      it do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "age" => { "type" => "string" },
            "email" => { "type" => "string" },
            "id" => { "type" => "string" },
            "name" => { "type" => "string" }
          }
        })
      end
    end

    context "when fields are declared with strings" do
      let_blueprinter_class("UserBlueprint") do
        <<~'RUBY'
          fields "id", "name", "email"
        RUBY
      end

      it do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "id" => { "type" => "string" },
            "name" => { "type" => "string" },
            "email" => { "type" => "string" }
          }
        })
      end
    end

    context "with identifier" do
      let_blueprinter_class("UserBlueprint") do
        <<~'RUBY'
          identifier :uuid
        RUBY
      end

      it do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "uuid" => { "type" => "string" }
          }
        })
      end
    end

    context "with a single field" do
      let_blueprinter_class("UserBlueprint") do
        <<~'RUBY'
          field :email
        RUBY
      end

      it do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "email" => { "type" => "string" }
          }
        })
      end
    end

    context "with field name alias" do
      let_blueprinter_class("UserBlueprint") do
        <<~'RUBY'
          field :email, name: :login
        RUBY
      end

      it do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "login" => { "type" => "string" }
          }
        })
      end
    end

    context "when field alias is declared with string values" do
      let_blueprinter_class("UserBlueprint") do
        <<~'RUBY'
          field "email", name: "login"
        RUBY
      end

      it do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "login" => { "type" => "string" }
          }
        })
      end
    end

    context "with a block field" do
      let_blueprinter_class("UserBlueprint") do
        <<~'RUBY'
          field(:full_name) { |u| "#{u.first_name} #{u.last_name}" }
        RUBY
      end

      it do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "full_name" => { "type" => "string" }
          }
        })
      end
    end

    context "with a block field declared with string values" do
      let_blueprinter_class("UserBlueprint") do
        <<~'RUBY'
          field("full_name") { |u| "#{u.first_name} #{u.last_name}" }
        RUBY
      end

      it do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "full_name" => { "type" => "string" }
          }
        })
      end
    end

    context "with all declaration types combined" do
      let_blueprinter_class("UserBlueprint") do
        <<~'RUBY'
          identifier :uuid
          fields :id, :name, :age
          field :email, name: :login
          fields :first_name, :last_name
          field(:full_name) { |u| "#{u.first_name} #{u.last_name}" }
        RUBY
      end

      it do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "uuid" => { "type" => "string" },
            "id" => { "type" => "string" },
            "name" => { "type" => "string" },
            "age" => { "type" => "string" },
            "login" => { "type" => "string" },
            "first_name" => { "type" => "string" },
            "last_name" => { "type" => "string" },
            "full_name" => { "type" => "string" }
          }
        })
      end
    end

    context "with all declaration types combined with string values" do
      let_blueprinter_class("UserBlueprint") do
        <<~'RUBY'
          identifier :uuid
          fields "id", "name", "age"
          field "email", name: :login
        RUBY
      end

      it do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "uuid" => { "type" => "string" },
            "id" => { "type" => "string" },
            "name" => { "type" => "string" },
            "age" => { "type" => "string" },
            "login" => { "type" => "string" }
          }
        })
      end
    end

    context "ensures identifier appears first in properties regardless of definition order" do
      let_blueprinter_class("UserBlueprint") do
        <<~'RUBY'
          fields :name, :email
          identifier :uuid
        RUBY
      end
      it do
        expect(subject["properties"].keys.first).to eq("uuid")
      end
    end

    context "with inheritance from another blueprint" do
      let_blueprinter_class("BaseUserBlueprint") do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_blueprinter_class("UserBlueprint", parent: mocked_classes["BaseUserBlueprint"]) do
        <<~'RUBY'
          fields :email, :age
        RUBY
      end

      it "merges parent schema into child schema" do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "id" => { "type" => "string" },
            "name" => { "type" => "string" },
            "email" => { "type" => "string" },
            "age" => { "type" => "string" }
          }
        })
      end
    end

    context "when superclass is Base (should not merge)" do
      let_blueprinter_class("UserBlueprint") do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      it "does not attempt to parse superclass" do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "id" => { "type" => "string" },
            "name" => { "type" => "string" }
          }
        })
      end
    end

    context "when child blueprint overrides a parent field" do
      let_blueprinter_class("BaseUserBlueprint") do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_blueprinter_class("UserBlueprint", parent: mocked_classes["BaseUserBlueprint"]) do
        <<~'RUBY'
          fields :name, :email
        RUBY
      end

      it "child fields take precedence" do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "id" => { "type" => "string" },
            "name" => { "type" => "string" },
            "email" => { "type" => "string" }
          }
        })
      end
    end

    context "with multiple levels of inheritance" do
      let_blueprinter_class("GrandparentBlueprint") do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_blueprinter_class("ParentBlueprint", parent: mocked_classes["GrandparentBlueprint"]) do
        <<~'RUBY'
          fields :email
        RUBY
      end

      let_blueprinter_class("UserBlueprint", parent: mocked_classes["ParentBlueprint"]) do
        <<~'RUBY'
          fields :age
        RUBY
      end

      it do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "id" => { "type" => "string" },
            "name" => { "type" => "string" },
            "email" => { "type" => "string" },
            "age" => { "type" => "string" }
          }
        })
      end
    end

    context "with identifier in parent blueprint" do
      let_blueprinter_class("BaseUserBlueprint") do
        <<~'RUBY'
          identifier :uuid
          fields :name
        RUBY
      end

      let_blueprinter_class("UserBlueprint", parent: mocked_classes["BaseUserBlueprint"]) do
        <<~'RUBY'
          identifier :id
          fields :email
        RUBY
      end

      it "inherits identifier from parent" do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "uuid" => { "type" => "string" },
            "id" => { "type" => "string" },
            "name" => { "type" => "string" },
            "email" => { "type" => "string" }
          }
        })
        expect(subject["properties"].keys.first).to eq("uuid")
        expect(subject["properties"].keys[1]).to eq("id")
      end
    end

    context "with a basic association" do
      let_blueprinter_class("ProjectBlueprint") do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_blueprinter_class("UserBlueprint") do
        <<~'RUBY'
          fields :email
          association :projects, blueprint: ProjectBlueprint
        RUBY
      end

      it "defaults to array type with nested blueprint schema" do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "email" => { "type" => "string" },
            "projects" => {
              "type" => "array",
              "items" => {
                "type" => "object",
                "properties" => {
                  "id" => { "type" => "string" },
                  "name" => { "type" => "string" }
                }
              }
            }
          }
        })
      end
    end

    context "with association name alias" do
      let_blueprinter_class("ProjectBlueprint") do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_blueprinter_class("UserBlueprint") do
        <<~'RUBY'
          fields :email
          association :projects, blueprint: ProjectBlueprint, name: :work_projects
        RUBY
      end

      it "uses the name alias as the association key" do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "email" => { "type" => "string" },
            "work_projects" => {
              "type" => "array",
              "items" => {
                "type" => "object",
                "properties" => {
                  "id" => { "type" => "string" },
                  "name" => { "type" => "string" }
                }
              }
            }
          }
        })
      end
    end

    context "with circular association" do
      let_blueprinter_class("ProjectBlueprint") do
        <<~'RUBY'
          fields :name
          association :users, blueprint: UserBlueprint
        RUBY
      end

      let_blueprinter_class("UserBlueprint") do
        <<~'RUBY'
          fields :email
          association :projects, blueprint: ProjectBlueprint
        RUBY
      end

      it "does not loop infinitely and falls back to $ref for circular reference" do
        expect { subject }.not_to raise_error
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "email" => { "type" => "string" },
            "projects" => {
              "type" => "array",
              "items" => {
                "type" => "object",
                "properties" => {
                  "name" => { "type" => "string" },
                  "users" => {
                    "type" => "array",
                    "items" => { "$ref" => "#/components/schemas/UserBlueprint" }
                  }
                }
              }
            }
          }
        })
      end
    end

    context "with association across multiple levels of inheritance" do
      let_blueprinter_class("TagBlueprint") do
        <<~'RUBY'
          fields :id, :label
        RUBY
      end

      let_blueprinter_class("ProjectBlueprint") do
        <<~'RUBY'
          fields :name
          association :tags, blueprint: TagBlueprint
        RUBY
      end

      let_blueprinter_class("BaseUserBlueprint") do
        <<~'RUBY'
          fields :email
          association :projects, blueprint: ProjectBlueprint
        RUBY
      end

      let_blueprinter_class("UserBlueprint", parent: mocked_classes["BaseUserBlueprint"]) do
        <<~'RUBY'
          fields :first_name
        RUBY
      end

      it "includes identifier in collection items" do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "email" => { "type" => "string" },
            "first_name" => { "type" => "string" },
            "projects" => {
              "type" => "array",
              "items" => {
                "type" => "object",
                "properties" => {
                  "name" => { "type" => "string" },
                  "tags" => {
                    "type" => "array",
                    "items" => {
                      "type" => "object",
                      "properties" => {
                        "id" => { "type" => "string" },
                        "label" => { "type" => "string" }
                      }
                    }
                  }
                }
              }
            }
          }
        })
      end
    end

    context "with identifier in associated blueprint" do
      let_blueprinter_class("ProjectBlueprint") do
        <<~'RUBY'
          identifier :uuid
          fields :name
        RUBY
      end

      let_blueprinter_class("UserBlueprint") do
        <<~'RUBY'
          identifier :id
          fields :email
          association :projects, blueprint: ProjectBlueprint
        RUBY
      end

      it "includes identifier in nested blueprint schema" do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "id" => { "type" => "string" },
            "email" => { "type" => "string" },
            "projects" => {
              "type" => "array",
              "items" => {
                "type" => "object",
                "properties" => {
                  "uuid" => { "type" => "string" },
                  "name" => { "type" => "string" }
                }
              }
            }
          }
        })
      end

      it "ensures identifier appears first in properties" do
        expect(subject["properties"].keys.first).to eq("id")
        expect(subject.dig("properties", "projects", "items", "properties").keys.first).to eq("uuid")
      end
    end

    context "with circular association through inheritance" do
      let_blueprinter_class("BaseProjectBlueprint") do
        <<~'RUBY'
          fields :name
        RUBY
      end

      let_blueprinter_class("ProjectBlueprint", parent: mocked_classes["BaseProjectBlueprint"]) do
        <<~'RUBY'
          fields :description
          association :users, blueprint: UserBlueprint
        RUBY
      end

      let_blueprinter_class("UserBlueprint") do
        <<~'RUBY'
          fields :email
          association :projects, blueprint: ProjectBlueprint
        RUBY
      end

      it "does not loop infinitely and falls back to $ref for circular reference" do
        expect { subject }.not_to raise_error
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "email" => { "type" => "string" },
            "projects" => {
              "type" => "array",
              "items" => {
                "type" => "object",
                "properties" => {
                  "description" => { "type" => "string" },
                  "name" => { "type" => "string" },
                  "users" => {
                    "type" => "array",
                    "items" => { "$ref" => "#/components/schemas/UserBlueprint" }
                  }
                }
              }
            }
          }
        })
      end
    end

    context "with multiple associations" do
      let_blueprinter_class("ProjectBlueprint") do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_blueprinter_class("TeamBlueprint") do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_blueprinter_class("UserBlueprint") do
        <<~'RUBY'
          fields :email
          association :projects, blueprint: ProjectBlueprint
          association :teams, blueprint: TeamBlueprint
        RUBY
      end

      it "includes schemas for all associations" do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "email" => { "type" => "string" },
            "projects" => {
              "type" => "array",
              "items" => {
                "type" => "object",
                "properties" => {
                  "id" => { "type" => "string" },
                  "name" => { "type" => "string" }
                }
              }
            },
            "teams" => {
              "type" => "array",
              "items" => {
                "type" => "object",
                "properties" => {
                  "id" => { "type" => "string" },
                  "name" => { "type" => "string" }
                }
              }
            }
          }
        })
      end
    end

    context "with namespaced association" do
      let_blueprinter_class("V1::ProjectBlueprint") do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_blueprinter_class("UserBlueprint") do
        <<~'RUBY'
          fields :email
          association :projects, blueprint: V1::ProjectBlueprint
        RUBY
      end

      it "resolves namespaced blueprint" do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "email" => { "type" => "string" },
            "projects" => {
              "type" => "array",
              "items" => {
                "type" => "object",
                "properties" => {
                  "id" => { "type" => "string" },
                  "name" => { "type" => "string" }
                }
              }
            }
          }
        })
      end
    end

    context "with a blueprint: Proc that ignores its argument" do
      let(:resource) { "ConstLambdaParent" }

      let_blueprinter_class("ProjectBlueprint") do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_blueprinter_class("ConstLambdaParent") do
        <<~'RUBY'
          field :email
          association :projects, name: :classmates, blueprint: ->(_) { ProjectBlueprint }
        RUBY
      end

      it "returns generic object schema for a Proc blueprint without resolving it" do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "email" => { "type" => "string" },
            "classmates" => {
              "type" => "array",
              "items" => { "type" => "object" }
            }
          }
        })
      end

      it "does not raise" do
        expect { subject }.not_to raise_error
      end
    end

    context "with a proc that branches on the parent object (not statically resolvable)" do
      let(:resource) { "BranchingUserBlueprint" }

      let_blueprinter_class("DataMiningBase") do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_blueprinter_class("DataMiningExtended") do
        <<~'RUBY'
          fields :id, :name, :uuid
        RUBY
      end

      let_blueprinter_class("BranchingUserBlueprint") do
        <<~'RUBY'
          fields :email, :subject
          association :projects,
                      blueprint: ->(parent) {
                        parent[:subject] == "Graph Theroy" ? DataMiningExtended : DataMiningBase
                      }
        RUBY
      end

      it "does not raise NoMethodError for undefined method 'reflections' on Proc" do
        expect { subject }.not_to raise_error
      end

      it "returns generic object schema for unresolvable Proc blueprint" do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "email" => { "type" => "string" },
            "subject" => { "type" => "string" },
            "projects" => {
              "type" => "array",
              "items" => { "type" => "object" }
            }
          }
        })
      end
    end

    context "with a circular association expressed as a Proc" do
      let(:resource) { "RecursiveNodeBlueprint" }

      let_blueprinter_class("RecursiveNodeBlueprint") do
        <<~RUBY
          field :id
          association :children, blueprint: ->(_) { RecursiveNodeBlueprint }
        RUBY
      end

      it "does not infinite-loop and returns generic object schema for Proc blueprint" do
        expect { subject }.not_to raise_error
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "id" => { "type" => "string" },
            "children" => {
              "type" => "array",
              "items" => { "type" => "object" }
            }
          }
        })
      end
    end

    context "with a pluralized association name" do
      let(:resource) { "PluralizedBlueprint" }

      let_blueprinter_class("ProjectBlueprint") do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_blueprinter_class("PluralizedBlueprint") do
        <<~'RUBY'
          fields :email
          association :projects, blueprint: ProjectBlueprint
        RUBY
      end

      it "renders as an array" do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "email" => { "type" => "string" },
            "projects" => {
              "type" => "array",
              "items" => {
                "type" => "object",
                "properties" => {
                  "id" => { "type" => "string" },
                  "name" => { "type" => "string" }
                }
              }
            }
          }
        })
      end
    end

    context "with a singular association name" do
      let(:resource) { "SingularBlueprint" }

      let_blueprinter_class("ProjectBlueprint") do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_blueprinter_class("SingularBlueprint") do
        <<~'RUBY'
          fields :email
          association :project, blueprint: ProjectBlueprint
        RUBY
      end

      it "renders as a single object, not array-wrapped" do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "email" => { "type" => "string" },
            "project" => {
              "type" => "object",
              "properties" => {
                "id" => { "type" => "string" },
                "name" => { "type" => "string" }
              }
            }
          }
        })
      end
    end

    context "with a singular association name when ActiveSupport's singularize is unavailable" do
      let(:resource) { "ActiveBlueprint" }
      let_blueprinter_class("ProjectBlueprint") do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_blueprinter_class("ActiveBlueprint") do
        <<~'RUBY'
          fields :email
          association :project, blueprint: ProjectBlueprint
        RUBY
      end

      before do
        allow_any_instance_of(String).to receive(:respond_to?).and_call_original
        allow_any_instance_of(String).to receive(:respond_to?).with(:singularize).and_return(false)
      end

      it "falls back to array, since cardinality cannot be determined without singularize" do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "email" => { "type" => "string" },
            "project" => {
              "type" => "array",
              "items" => {
                "type" => "object",
                "properties" => {
                  "id" => { "type" => "string" },
                  "name" => { "type" => "string" }
                }
              }
            }
          }
        })
      end
    end

    context "with a pluralized association name and a singular name: alias" do
      let(:resource) { "PluralizedBlueprint" }

      let_blueprinter_class("ProjectBlueprint") do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_blueprinter_class("PluralizedBlueprint") do
        <<~'RUBY'
          fields :email
          association :projects, blueprint: ProjectBlueprint, name: :classmate
        RUBY
      end

      it "follows the alias, not the original association key" do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "email" => { "type" => "string" },
            "classmate" => {
              "type" => "array",
              "items" => {
                "type" => "object",
                "properties" => {
                  "id" => { "type" => "string" },
                  "name" => { "type" => "string" }
                }
              }
            }
          }
        })
      end
    end

    context "with an unresolvable dynamic blueprint on a singular association name" do
      let(:resource) { "DataBluePrint" }

      let_blueprinter_class("DataMiningBase") do
        <<~RUBY
          fields :id
        RUBY
      end

      let_blueprinter_class("DataMiningExtended") do
        <<~RUBY
          fields :id, :uuid
        RUBY
      end

      let_blueprinter_class("DataBluePrint") do
        <<~'RUBY'
          fields :email, :subject
          association :project,
                      blueprint: ->(parent) {
                        parent[:subject] == "Graph Theroy" ? DataMiningExtended : DataMiningBase
                      }
        RUBY
      end

      it "returns generic object schema for unresolvable Proc blueprint (no array wrapper, since name is singular)" do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "email" => { "type" => "string" },
            "subject" => { "type" => "string" },
            "project" => { "type" => "object" }
          }
        })
      end
    end

    context "known limitation: uncountable noun association name" do
      let(:resource) { "LimitationBlueprint" }

      let_blueprinter_class("DatumBlueprint") do
        <<~'RUBY'
          fields :id
        RUBY
      end

      let_blueprinter_class("LimitationBlueprint") do
        <<~'RUBY'
          fields :email
          association :data, blueprint: DatumBlueprint
        RUBY
      end

      it "correctly detects :data as a collection, since ActiveSupport singularizes it to :datum" do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "email" => { "type" => "string" },
            "data" => {
              "type" => "array",
              "items" => {
                "type" => "object",
                "properties" => {
                  "id" => { "type" => "string" }
                }
              }
            }
          }
        })
      end
    end

    context "known limitation: genuinely uncountable noun association name" do
      let(:resource) { "InformerBlueprint" }

      let_blueprinter_class("InfoBlueprint") do
        <<~'RUBY'
          fields :id
        RUBY
      end

      let_blueprinter_class("InformerBlueprint") do
        <<~'RUBY'
          fields :email
          association :information, blueprint: InfoBlueprint
        RUBY
      end

      it "is treated as a single object even if the real relationship is a collection" do
        is_expected.to eq({
          "type" => "object",
          "properties" => {
            "email" => { "type" => "string" },
            "information" => {
              "type" => "object",
              "properties" => {
                "id" => { "type" => "string" }
              }
            }
          }
        })
      end
    end
  end

  describe "collection" do
    let(:resource) { "Array<UserBlueprint>" }

    context "with basic fields" do
      let_blueprinter_class("UserBlueprint") do
        <<~'RUBY'
          fields :id, :name, :email
        RUBY
      end

      it do
        is_expected.to eq({
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "id" => { "type" => "string" },
              "name" => { "type" => "string" },
              "email" => { "type" => "string" }
            }
          }
        })
      end
    end

    context "with identifier" do
      let(:resource) { "[UserBlueprint]" }
      let_blueprinter_class("UserBlueprint") do
        <<~'RUBY'
          identifier :uuid
          fields :name, :email
        RUBY
      end

      it do
        is_expected.to eq({
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "uuid" => { "type" => "string" },
              "name" => { "type" => "string" },
              "email" => { "type" => "string" }
            }
          }
        })
      end
    end

    context "with inherited fields" do
      let_blueprinter_class("BaseUserBlueprint") do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_blueprinter_class("UserBlueprint", parent: mocked_classes["BaseUserBlueprint"]) do
        <<~'RUBY'
          fields :email
        RUBY
      end

      it do
        is_expected.to eq({
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "id" => { "type" => "string" },
              "name" => { "type" => "string" },
              "email" => { "type" => "string" }
            }
          }
        })
      end
    end

    context "with multiple levels of inheritance" do
      let_blueprinter_class("GrandparentBlueprint") do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end
      let_blueprinter_class("ParentBlueprint", parent: mocked_classes["GrandparentBlueprint"]) do
        <<~'RUBY'
          fields :email
        RUBY
      end
      let_blueprinter_class("UserBlueprint", parent: mocked_classes["ParentBlueprint"]) do
        <<~'RUBY'
          fields :age
        RUBY
      end
      it do
        is_expected.to eq({
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "id" => { "type" => "string" },
              "name" => { "type" => "string" },
              "email" => { "type" => "string" },
              "age" => { "type" => "string" }
            }
          }
        })
      end
    end

    context "with identifier in parent blueprint" do
      let_blueprinter_class("BaseUserBlueprint") do
        <<~'RUBY'
          identifier :uuid
          fields :name
        RUBY
      end
      let_blueprinter_class("UserBlueprint", parent: mocked_classes["BaseUserBlueprint"]) do
        <<~'RUBY'
          identifier :id
          fields :email
        RUBY
      end
      it "inherits identifier from parent" do
        is_expected.to eq({
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "uuid" => { "type" => "string" },
              "id" => { "type" => "string" },
              "name" => { "type" => "string" },
              "email" => { "type" => "string" }
            }
          }
        })
        expect(subject["items"]["properties"].keys.first).to eq("uuid")
        expect(subject["items"]["properties"].keys[1]).to eq("id")
      end
    end

    context "with a basic association" do
      let_blueprinter_class("ProjectBlueprint") do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_blueprinter_class("UserBlueprint") do
        <<~'RUBY'
          fields :email
          association :projects, blueprint: ProjectBlueprint
        RUBY
      end

      it "defaults to array type with nested blueprint schema" do
        is_expected.to eq({
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "email" => { "type" => "string" },
              "projects" => {
                "type" => "array",
                "items" => {
                  "type" => "object",
                  "properties" => {
                    "id" => { "type" => "string" },
                    "name" => { "type" => "string" }
                  }
                }
              }
            }
          }
        })
      end
    end

    context "with association name alias" do
      let_blueprinter_class("ProjectBlueprint") do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_blueprinter_class("UserBlueprint") do
        <<~'RUBY'
          fields :email
          association :projects, blueprint: ProjectBlueprint, name: :work_projects
        RUBY
      end

      it "uses the name alias as the association key" do
        is_expected.to eq({
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "email" => { "type" => "string" },
              "work_projects" => {
                "type" => "array",
                "items" => {
                  "type" => "object",
                  "properties" => {
                    "id" => { "type" => "string" },
                    "name" => { "type" => "string" }
                  }
                }
              }
            }
          }
        })
      end
    end

    context "with circular association" do
      let_blueprinter_class("ProjectBlueprint") do
        <<~'RUBY'
          fields :name
          association :users, blueprint: UserBlueprint
        RUBY
      end

      let_blueprinter_class("UserBlueprint") do
        <<~'RUBY'
          fields :email
          association :projects, blueprint: ProjectBlueprint
        RUBY
      end

      it "does not loop infinitely and falls back to $ref for circular reference" do
        expect { subject }.not_to raise_error
        is_expected.to eq({
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "email" => { "type" => "string" },
              "projects" => {
                "type" => "array",
                "items" => {
                  "type" => "object",
                  "properties" => {
                    "name" => { "type" => "string" },
                    "users" => {
                      "type" => "array",
                      "items" => { "$ref" => "#/components/schemas/UserBlueprint" }
                    }
                  }
                }
              }
            }
          }
        })
      end
    end

    context "with association across multiple levels of inheritance" do
      let_blueprinter_class("TagBlueprint") do
        <<~'RUBY'
          fields :id, :label
        RUBY
      end

      let_blueprinter_class("ProjectBlueprint") do
        <<~'RUBY'
          fields :name
          association :tags, blueprint: TagBlueprint
        RUBY
      end

      let_blueprinter_class("BaseUserBlueprint") do
        <<~'RUBY'
          fields :email
          association :projects, blueprint: ProjectBlueprint
        RUBY
      end

      let_blueprinter_class("UserBlueprint", parent: mocked_classes["BaseUserBlueprint"]) do
        <<~'RUBY'
          fields :first_name
        RUBY
      end

      it "inherits and resolves nested associations across multiple blueprint levels" do
        is_expected.to eq({
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "email" => { "type" => "string" },
              "first_name" => { "type" => "string" },
              "projects" => {
                "type" => "array",
                "items" => {
                  "type" => "object",
                  "properties" => {
                    "name" => { "type" => "string" },
                    "tags" => {
                      "type" => "array",
                      "items" => {
                        "type" => "object",
                        "properties" => {
                          "id" => { "type" => "string" },
                          "label" => { "type" => "string" }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        })
      end
    end

    context "with identifier in associated blueprint" do
      let_blueprinter_class("ProjectBlueprint") do
        <<~'RUBY'
          identifier :uuid
          fields :name
        RUBY
      end

      let_blueprinter_class("UserBlueprint") do
        <<~'RUBY'
          identifier :id
          fields :email
          association :projects, blueprint: ProjectBlueprint
        RUBY
      end

      it "includes identifier in nested blueprint schema" do
        is_expected.to eq({
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "id" => { "type" => "string" },
              "email" => { "type" => "string" },
              "projects" => {
                "type" => "array",
                "items" => {
                  "type" => "object",
                  "properties" => {
                    "uuid" => { "type" => "string" },
                    "name" => { "type" => "string" }
                  }
                }
              }
            }
          }
        })
      end

      it "ensures identifier appears first in properties" do
        expect(subject["items"]["properties"].keys.first).to eq("id")
        expect(subject.dig("items", "properties", "projects", "items", "properties").keys.first).to eq("uuid")
      end
    end

    context "with circular association through inheritance" do
      let_blueprinter_class("BaseProjectBlueprint") do
        <<~'RUBY'
          fields :name
        RUBY
      end

      let_blueprinter_class("ProjectBlueprint", parent: mocked_classes["BaseProjectBlueprint"]) do
        <<~'RUBY'
          fields :description
          association :users, blueprint: UserBlueprint
        RUBY
      end

      let_blueprinter_class("UserBlueprint") do
        <<~'RUBY'
          fields :email
          association :projects, blueprint: ProjectBlueprint
        RUBY
      end

      it "does not loop infinitely and falls back to $ref for circular reference" do
        expect { subject }.not_to raise_error
        is_expected.to eq({
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "email" => { "type" => "string" },
              "projects" => {
                "type" => "array",
                "items" => {
                  "type" => "object",
                  "properties" => {
                    "description" => { "type" => "string" },
                    "name" => { "type" => "string" },
                    "users" => {
                      "type" => "array",
                      "items" => { "$ref" => "#/components/schemas/UserBlueprint" }
                    }
                  }
                }
              }
            }
          }
        })
      end
    end

    context "with multiple associations" do
      let(:resource) { "Array<UserBlueprint>" }

      let_blueprinter_class("ProjectBlueprint") do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_blueprinter_class("TeamBlueprint") do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_blueprinter_class("UserBlueprint") do
        <<~'RUBY'
          fields :email
          association :projects, blueprint: ProjectBlueprint
          association :teams, blueprint: TeamBlueprint
        RUBY
      end

      it "includes schemas for all associations" do
        is_expected.to eq({
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "email" => { "type" => "string" },
              "projects" => {
                "type" => "array",
                "items" => {
                  "type" => "object",
                  "properties" => {
                    "id" => { "type" => "string" },
                    "name" => { "type" => "string" }
                  }
                }
              },
              "teams" => {
                "type" => "array",
                "items" => {
                  "type" => "object",
                  "properties" => {
                    "id" => { "type" => "string" },
                    "name" => { "type" => "string" }
                  }
                }
              }
            }
          }
        })
      end
    end

    context "with namespaced association" do
      let(:resource) { "Array<UserBlueprint>" }

      let_blueprinter_class("V1::ProjectBlueprint") do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_blueprinter_class("UserBlueprint") do
        <<~'RUBY'
          fields :email
          association :projects, blueprint: V1::ProjectBlueprint
        RUBY
      end

      it "resolves namespaced blueprint" do
        is_expected.to eq({
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "email" => { "type" => "string" },
              "projects" => {
                "type" => "array",
                "items" => {
                  "type" => "object",
                  "properties" => {
                    "id" => { "type" => "string" },
                    "name" => { "type" => "string" }
                  }
                }
              }
            }
          }
        })
      end
    end

    context "with a blueprint: Proc that ignores its argument" do
      let(:resource) { "Array<ConstLambdaParentCollection>" }

      let_blueprinter_class("ProjectBlueprint") do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_blueprinter_class("ConstLambdaParentCollection") do
        <<~'RUBY'
          field :email
          association :projects, name: :classmates, blueprint: ->(_) { ProjectBlueprint }
        RUBY
      end

      it "returns generic object schema for a Proc blueprint without resolving it" do
        is_expected.to eq({
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "email" => { "type" => "string" },
              "classmates" => {
                "type" => "array",
                "items" => { "type" => "object" }
              }
            }
          }
        })
      end

      it "does not raise" do
        expect { subject }.not_to raise_error
      end
    end

    context "with a proc that branches on the parent object (not statically resolvable)" do
      let(:resource) { "Array<BranchingUserBlueprintCollection>" }

      let_blueprinter_class("DataMiningBase") do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_blueprinter_class("DataMiningExtended") do
        <<~'RUBY'
          fields :id, :name, :uuid
        RUBY
      end

      let_blueprinter_class("BranchingUserBlueprintCollection") do
        <<~'RUBY'
          fields :email, :subject
          association :projects,
                      blueprint: ->(parent) {
                        parent[:subject] == "Graph Theroy" ? DataMiningExtended : DataMiningBase
                      }
        RUBY
      end

      it "does not raise NoMethodError for undefined method 'reflections' on Proc" do
        expect { subject }.not_to raise_error
      end

      it "returns generic object schema for unresolvable Proc blueprint" do
        is_expected.to eq({
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "email" => { "type" => "string" },
              "subject" => { "type" => "string" },
              "projects" => {
                "type" => "array",
                "items" => { "type" => "object" }
              }
            }
          }
        })
      end
    end

    context "with a circular association expressed as a Proc" do
      let(:resource) { "Array<RecursiveNodeBlueprintCollection>" }

      let_blueprinter_class("RecursiveNodeBlueprintCollection") do
        <<~'RUBY'
          field :id
          association :children, blueprint: ->(_) { RecursiveNodeBlueprintCollection }
        RUBY
      end

      it "does not infinite-loop and returns generic object schema for Proc blueprint" do
        expect { subject }.not_to raise_error
        is_expected.to eq({
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "id" => { "type" => "string" },
              "children" => {
                "type" => "array",
                "items" => { "type" => "object" }
              }
            }
          }
        })
      end
    end

    context "with a pluralized association name" do
      let(:resource) { "Array<PluralizedBlueprintCollection>" }

      let_blueprinter_class("ProjectBlueprint") do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_blueprinter_class("PluralizedBlueprintCollection") do
        <<~'RUBY'
          fields :email
          association :projects, blueprint: ProjectBlueprint
        RUBY
      end

      it "renders as an array" do
        is_expected.to eq({
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "email" => { "type" => "string" },
              "projects" => {
                "type" => "array",
                "items" => {
                  "type" => "object",
                  "properties" => {
                    "id" => { "type" => "string" },
                    "name" => { "type" => "string" }
                  }
                }
              }
            }
          }
        })
      end
    end

    context "with a singular association name" do
      let(:resource) { "Array<SingularBlueprintCollection>" }

      let_blueprinter_class("ProjectBlueprint") do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_blueprinter_class("SingularBlueprintCollection") do
        <<~'RUBY'
          fields :email
          association :project, blueprint: ProjectBlueprint
        RUBY
      end

      it "renders as a single object, not array-wrapped" do
        is_expected.to eq({
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "email" => { "type" => "string" },
              "project" => {
                "type" => "object",
                "properties" => {
                  "id" => { "type" => "string" },
                  "name" => { "type" => "string" }
                }
              }
            }
          }
        })
      end
    end

    context "with a singular association name when ActiveSupport's singularize is unavailable" do
      let(:resource) { "Array<ActiveBlueprintCollection>" }

      let_blueprinter_class("ProjectBlueprint") do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_blueprinter_class("ActiveBlueprintCollection") do
        <<~'RUBY'
          fields :email
          association :project, blueprint: ProjectBlueprint
        RUBY
      end

      before do
        allow_any_instance_of(String).to receive(:respond_to?).and_call_original
        allow_any_instance_of(String).to receive(:respond_to?).with(:singularize).and_return(false)
      end

      it "falls back to array, since cardinality cannot be determined without singularize" do
        is_expected.to eq({
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "email" => { "type" => "string" },
              "project" => {
                "type" => "array",
                "items" => {
                  "type" => "object",
                  "properties" => {
                    "id" => { "type" => "string" },
                    "name" => { "type" => "string" }
                  }
                }
              }
            }
          }
        })
      end
    end

    context "with a pluralized association name and a singular name: alias" do
      let(:resource) { "Array<PluralizedAliasBlueprintCollection>" }

      let_blueprinter_class("ProjectBlueprint") do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_blueprinter_class("PluralizedAliasBlueprintCollection") do
        <<~'RUBY'
          fields :email
          association :projects, blueprint: ProjectBlueprint, name: :classmate
        RUBY
      end

      it "follows the alias, not the original association key" do
        is_expected.to eq({
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "email" => { "type" => "string" },
              "classmate" => {
                "type" => "array",
                "items" => {
                  "type" => "object",
                  "properties" => {
                    "id" => { "type" => "string" },
                    "name" => { "type" => "string" }
                  }
                }
              }
            }
          }
        })
      end
    end

    context "with an unresolvable dynamic blueprint on a singular association name" do
      let(:resource) { "Array<DataBluePrintCollection>" }

      let_blueprinter_class("DataMiningBase") do
        <<~'RUBY'
          fields :id
        RUBY
      end

      let_blueprinter_class("DataMiningExtended") do
        <<~'RUBY'
          fields :id, :uuid
        RUBY
      end

      let_blueprinter_class("DataBluePrintCollection") do
        <<~'RUBY'
          fields :email, :subject
          association :project,
                      blueprint: ->(parent) {
                        parent[:subject] == "Graph Theroy" ? DataMiningExtended : DataMiningBase
                      }
        RUBY
      end

      it "returns generic object schema for unresolvable Proc blueprint (no array wrapper, since name is singular)" do
        is_expected.to eq({
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "email" => { "type" => "string" },
              "subject" => { "type" => "string" },
              "project" => { "type" => "object" }
            }
          }
        })
      end
    end

    context "known limitation: uncountable noun association name" do
      let(:resource) { "Array<LimitationBlueprintCollection>" }

      let_blueprinter_class("DatumBlueprint") do
        <<~'RUBY'
          fields :id
        RUBY
      end

      let_blueprinter_class("LimitationBlueprintCollection") do
        <<~'RUBY'
          fields :email
          association :data, blueprint: DatumBlueprint
        RUBY
      end

      it "correctly detects :data as a collection, since ActiveSupport singularizes it to :datum" do
        is_expected.to eq({
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "email" => { "type" => "string" },
              "data" => {
                "type" => "array",
                "items" => {
                  "type" => "object",
                  "properties" => {
                    "id" => { "type" => "string" }
                  }
                }
              }
            }
          }
        })
      end
    end

    context "known limitation: genuinely uncountable noun association name" do
      let(:resource) { "Array<InformerBlueprintCollection>" }

      let_blueprinter_class("InfoBlueprint") do
        <<~'RUBY'
          fields :id
        RUBY
      end

      let_blueprinter_class("InformerBlueprintCollection") do
        <<~'RUBY'
          fields :email
          association :information, blueprint: InfoBlueprint
        RUBY
      end

      it "is treated as a single object even if the real relationship is a collection" do
        is_expected.to eq({
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "email" => { "type" => "string" },
              "information" => {
                "type" => "object",
                "properties" => {
                  "id" => { "type" => "string" }
                }
              }
            }
          }
        })
      end
    end
  end
end
