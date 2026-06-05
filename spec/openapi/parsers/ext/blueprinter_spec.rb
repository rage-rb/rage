# frozen_string_literal: true

require "prism"

RSpec.describe Rage::OpenAPI::Parsers::Ext::Blueprinter do
  include_context "mocked_classes"

  subject { described_class.new(**options).parse(resource) }

  let(:options) { {} }

  describe "single object" do
    let(:resource) { "UserBlueprint" }

    context "with an empty blueprint" do
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
          end
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object" })
      end
    end

    context "with basic fields" do
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            fields :id, :name, :email, :age
          end
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

    context "when fields are declared with strings" do
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            fields "id", "name", "email"
          end
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
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            identifier :uuid
          end
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
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            field :email
          end
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
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            field :email, name: :login
          end
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
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            field "email", name: "login"
          end
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
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            field(:full_name) { |u| "#{u.first_name} #{u.last_name}" }
          end
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
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            field("full_name") { |u| "#{u.first_name} #{u.last_name}" }
          end
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
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            identifier :uuid
            fields :id, :name, :age
            field :email, name: :login
            fields :first_name, :last_name
            field(:full_name) { |u| "#{u.first_name} #{u.last_name}" }
          end
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
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            identifier :uuid
            fields "id", "name", "age"
            field "email", name: "login"
            fields "first_name", "last_name"
            field("full_name") { |u| "#{u.first_name} #{u.last_name}" }
          end
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

    context "with all declaration types combined with string and symbol vales" do
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            identifier :uuid
            fields :id, "name", :age
            field :email, name: "login"
            fields "first_name", :last_name
            field("full_name") { |u| "#{u.first_name} #{u.last_name}" }
          end
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

    context "ensures identifier appears first in properties regardless of definition order" do
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            fields :name, :email
            identifier :uuid
          end
        RUBY
      end
      it do
        expect(subject["properties"].keys.first).to eq("uuid")
      end
    end

    context "with inheritance from another blueprint" do
      let_class("BaseUserBlueprint") do
        <<~'RUBY'
          class BaseUserBlueprint < Blueprinter::Base
            fields :id, :name
          end
        RUBY
      end

      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < BaseUserBlueprint
            fields :email, :age
          end
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
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            fields :id, :name
          end
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
      let_class("BaseUserBlueprint") do
        <<~'RUBY'
          class BaseUserBlueprint < Blueprinter::Base
            fields :id, :name
          end
        RUBY
      end

      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < BaseUserBlueprint
            fields :name, :email
          end
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
      let_class("GrandparentBlueprint") do
        <<~'RUBY'
          class GrandparentBlueprint < Blueprinter::Base
            fields :id, :name
          end
        RUBY
      end

      let_class("ParentBlueprint") do
        <<~'RUBY'
          class ParentBlueprint < GrandparentBlueprint
            fields :email
          end
        RUBY
      end

      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < ParentBlueprint
            fields :age
          end
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
      let_class("BaseUserBlueprint") do
        <<~'RUBY'
          class BaseUserBlueprint < Blueprinter::Base
            identifier :uuid
            fields :name
          end
        RUBY
      end

      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < BaseUserBlueprint
            identifier :id
            fields :email
          end
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
      let_class("ProjectBlueprint") do
        <<~'RUBY'
          class ProjectBlueprint < Blueprinter::Base
            fields :id, :name
          end
        RUBY
      end

      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            fields :email
            association :projects, blueprint: ProjectBlueprint
          end
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
      let_class("ProjectBlueprint") do
        <<~'RUBY'
          class ProjectBlueprint < Blueprinter::Base
            fields :id, :name
          end
        RUBY
      end

      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            fields :email
            association :projects, blueprint: ProjectBlueprint, name: :work_projects
          end
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

      context "when referenced blueprint cannot be resolved" do
        let_class("UserBlueprint") do
          <<~'RUBY'
            class UserBlueprint < Blueprinter::Base
              fields :email
              association :projects, blueprint: UnknownBlueprint
            end
          RUBY
        end

        it "falls back to empty object schema" do
          is_expected.to eq({
            "type" => "object",
            "properties" => {
              "email" => { "type" => "string" },
              "projects" => {
                "type" => "array",
                "items" => { "type" => "object" }
              }
            }
          })
        end
      end

      context "with circular association" do
        let_class("ProjectBlueprint") do
          <<~'RUBY'
            class ProjectBlueprint < Blueprinter::Base
              fields :name
              association :user, blueprint: UserBlueprint
            end
          RUBY
        end

        let_class("UserBlueprint") do
          <<~'RUBY'
            class UserBlueprint < Blueprinter::Base
              fields :email
              association :projects, blueprint: ProjectBlueprint
            end
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
                    "user" => {
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
    end

    context "with association across multiple levels of inheritance" do
      let_class("TagBlueprint") do
        <<~'RUBY'
          class TagBlueprint < Blueprinter::Base
            fields :id, :label
          end
        RUBY
      end

      let_class("ProjectBlueprint") do
        <<~'RUBY'
          class ProjectBlueprint < Blueprinter::Base
            fields :name
            association :tags, blueprint: TagBlueprint
          end
        RUBY
      end

      let_class("BaseUserBlueprint") do
        <<~'RUBY'
          class BaseUserBlueprint < Blueprinter::Base
            fields :email
            association :projects, blueprint: ProjectBlueprint
          end
        RUBY
      end

      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < BaseUserBlueprint
            fields :first_name
          end
        RUBY
      end

      it do
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
      let_class("ProjectBlueprint") do
        <<~'RUBY'
          class ProjectBlueprint < Blueprinter::Base
            identifier :uuid
            fields :name
          end
        RUBY
      end

      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            identifier :id
            fields :email
            association :projects, blueprint: ProjectBlueprint
          end
        RUBY
      end

      it do
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
  end

  describe "collection" do
    let(:resource) { "Array<UserBlueprint>" }

    context "with basic fields" do
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            fields :id, :name, :email
          end
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
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            identifier :uuid
            fields :name, :email
          end
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
      let_class("BaseUserBlueprint") do
        <<~'RUBY'
          class BaseUserBlueprint < Blueprinter::Base
            fields :id, :name
          end
        RUBY
      end

      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < BaseUserBlueprint
            fields :email
          end
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
      let_class("GrandparentBlueprint") do
        <<~'RUBY'
          class GrandparentBlueprint < Blueprinter::Base
            fields :id, :name
          end
        RUBY
      end
      let_class("ParentBlueprint") do
        <<~'RUBY'
          class ParentBlueprint < GrandparentBlueprint
            fields :email
          end
        RUBY
      end
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < ParentBlueprint
            fields :age
          end
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
      let_class("BaseUserBlueprint") do
        <<~'RUBY'
          class BaseUserBlueprint < Blueprinter::Base
            identifier :uuid
            fields :name
          end
        RUBY
      end
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < BaseUserBlueprint
            identifier :id
            fields :email
          end
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
      let_class("ProjectBlueprint") do
        <<~'RUBY'
          class ProjectBlueprint < Blueprinter::Base
            fields :id, :name
          end
        RUBY
      end

      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            fields :email
            association :projects, blueprint: ProjectBlueprint
          end
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
      let_class("ProjectBlueprint") do
        <<~'RUBY'
          class ProjectBlueprint < Blueprinter::Base
            fields :id, :name
          end
        RUBY
      end

      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            fields :email
            association :projects, blueprint: ProjectBlueprint, name: :work_projects
          end
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

    context "when referenced blueprint cannot be resolved" do
      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            fields :email
            association :projects, blueprint: UnknownBlueprint
          end
        RUBY
      end

      it "falls back to empty object schema" do
        is_expected.to eq({
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "email" => { "type" => "string" },
              "projects" => {
                "type" => "array",
                "items" => { "type" => "object" }
              }
            }
          }
        })
      end
    end

    context "with circular association" do
      let_class("ProjectBlueprint") do
        <<~'RUBY'
          class ProjectBlueprint < Blueprinter::Base
            fields :name
            association :user, blueprint: UserBlueprint
          end
        RUBY
      end

      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            fields :email
            association :projects, blueprint: ProjectBlueprint
          end
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
                    "user" => {
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
      let_class("TagBlueprint") do
        <<~'RUBY'
          class TagBlueprint < Blueprinter::Base
            fields :id, :label
          end
        RUBY
      end

      let_class("ProjectBlueprint") do
        <<~'RUBY'
          class ProjectBlueprint < Blueprinter::Base
            fields :name
            association :tags, blueprint: TagBlueprint
          end
        RUBY
      end

      let_class("BaseUserBlueprint") do
        <<~'RUBY'
          class BaseUserBlueprint < Blueprinter::Base
            fields :email
            association :projects, blueprint: ProjectBlueprint
          end
        RUBY
      end

      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < BaseUserBlueprint
            fields :first_name
          end
        RUBY
      end

      it do
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
      let_class("ProjectBlueprint") do
        <<~'RUBY'
          class ProjectBlueprint < Blueprinter::Base
            identifier :uuid
            fields :name
          end
        RUBY
      end

      let_class("UserBlueprint") do
        <<~'RUBY'
          class UserBlueprint < Blueprinter::Base
            identifier :id
            fields :email
            association :projects, blueprint: ProjectBlueprint
          end
        RUBY
      end

      it do
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
  end
end
