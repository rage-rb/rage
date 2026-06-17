# frozen_string_literal: true

require "blueprinter"

RSpec.describe Rage::OpenAPI::Parsers::Ext::Blueprinter do
  include_context "mocked_classes"

  subject { described_class.new(**options).parse(resource) }

  let(:options) { {} }

  describe "single object" do
    let(:resource) { "UserBlueprint" }

    context "with an empty blueprint" do
      let_class("UserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object" })
      end
    end

    context "with basic fields" do
      let_class("UserBlueprint", parent: Blueprinter::Base) do
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
      let_class("UserBlueprint", parent: Blueprinter::Base) do
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
      let_class("UserBlueprint", parent: Blueprinter::Base) do
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
      let_class("UserBlueprint", parent: Blueprinter::Base) do
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
      let_class("UserBlueprint", parent: Blueprinter::Base) do
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
      let_class("UserBlueprint", parent: Blueprinter::Base) do
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
      let_class("UserBlueprint", parent: Blueprinter::Base) do
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
      let_class("UserBlueprint", parent: Blueprinter::Base) do
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
      let_class("UserBlueprint", parent: Blueprinter::Base) do
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
      let_class("UserBlueprint", parent: Blueprinter::Base) do
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
      let_class("UserBlueprint", parent: Blueprinter::Base) do
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
      let_class("BaseUserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_class("UserBlueprint", parent: mocked_classes["BaseUserBlueprint"]) do
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
      let_class("UserBlueprint", parent: Blueprinter::Base) do
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
      let_class("BaseUserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_class("UserBlueprint", parent: mocked_classes["BaseUserBlueprint"]) do
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
      let_class("GrandparentBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_class("ParentBlueprint", parent: mocked_classes["GrandparentBlueprint"]) do
        <<~'RUBY'
          fields :email
        RUBY
      end

      let_class("UserBlueprint", parent: mocked_classes["ParentBlueprint"]) do
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
      let_class("BaseUserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          identifier :uuid
          fields :name
        RUBY
      end

      let_class("UserBlueprint", parent: mocked_classes["BaseUserBlueprint"]) do
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
      let_class("ProjectBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_class("UserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :email
          association :projects, blueprint: ProjectBlueprint
        RUBY
      end

      before { ProjectBlueprint }

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
      let_class("ProjectBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_class("UserBlueprint", parent: Blueprinter::Base) do
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
      let_class("ProjectBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :name
          association :user, blueprint: UserBlueprint
        RUBY
      end

      let_class("UserBlueprint", parent: Blueprinter::Base) do
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

    context "with association across multiple levels of inheritance" do
      let_class("TagBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :id, :label
        RUBY
      end

      let_class("ProjectBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :name
          association :tags, blueprint: TagBlueprint
        RUBY
      end

      let_class("BaseUserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :email
          association :projects, blueprint: ProjectBlueprint
        RUBY
      end

      let_class("UserBlueprint", parent: mocked_classes["BaseUserBlueprint"]) do
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
      let_class("ProjectBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          identifier :uuid
          fields :name
        RUBY
      end

      let_class("UserBlueprint", parent: Blueprinter::Base) do
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
      let_class("BaseProjectBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :name
        RUBY
      end

      let_class("ProjectBlueprint", parent: mocked_classes["BaseProjectBlueprint"]) do
        <<~'RUBY'
          fields :description
          association :user, blueprint: UserBlueprint
        RUBY
      end

      let_class("UserBlueprint", parent: Blueprinter::Base) do
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

    context "with multiple associations" do
      let_class("ProjectBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_class("TeamBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_class("UserBlueprint", parent: Blueprinter::Base) do
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
      unless Object.const_defined?(:V1)
        Object.const_set(:V1, Module.new)
      end
      V1::ProjectBlueprint = Class.new(Blueprinter::Base)
      V1::ProjectBlueprint.class_eval do
        fields :id, :name
      end

      let_class("UserBlueprint", parent: Blueprinter::Base) do
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
  end

  describe "collection" do
    let(:resource) { "Array<UserBlueprint>" }

    context "with basic fields" do
      let_class("UserBlueprint", parent: Blueprinter::Base) do
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
      let_class("UserBlueprint", parent: Blueprinter::Base) do
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
      let_class("BaseUserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_class("UserBlueprint", parent: mocked_classes["BaseUserBlueprint"]) do
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
      let_class("GrandparentBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end
      let_class("ParentBlueprint", parent: mocked_classes["GrandparentBlueprint"]) do
        <<~'RUBY'
          fields :email
        RUBY
      end
      let_class("UserBlueprint", parent: mocked_classes["ParentBlueprint"]) do
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
      let_class("BaseUserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          identifier :uuid
          fields :name
        RUBY
      end
      let_class("UserBlueprint", parent: mocked_classes["BaseUserBlueprint"]) do
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
      let_class("ProjectBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_class("UserBlueprint", parent: Blueprinter::Base) do
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
      let_class("ProjectBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_class("UserBlueprint", parent: Blueprinter::Base) do
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
      let_class("ProjectBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :name
          association :user, blueprint: UserBlueprint
        RUBY
      end

      let_class("UserBlueprint", parent: Blueprinter::Base) do
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
      let_class("TagBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :id, :label
        RUBY
      end

      let_class("ProjectBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :name
          association :tags, blueprint: TagBlueprint
        RUBY
      end

      let_class("BaseUserBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :email
          association :projects, blueprint: ProjectBlueprint
        RUBY
      end

      let_class("UserBlueprint", parent: mocked_classes["BaseUserBlueprint"]) do
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
      let_class("ProjectBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          identifier :uuid
          fields :name
        RUBY
      end

      let_class("UserBlueprint", parent: Blueprinter::Base) do
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
      let_class("BaseProjectBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :name
        RUBY
      end

      let_class("ProjectBlueprint", parent: mocked_classes["BaseProjectBlueprint"]) do
        <<~'RUBY'
          fields :description
          association :user, blueprint: UserBlueprint
        RUBY
      end

      let_class("UserBlueprint", parent: Blueprinter::Base) do
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

    context "with multiple associations" do
      let(:resource) { "Array<UserBlueprint>" }

      let_class("ProjectBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_class("TeamBlueprint", parent: Blueprinter::Base) do
        <<~'RUBY'
          fields :id, :name
        RUBY
      end

      let_class("UserBlueprint", parent: Blueprinter::Base) do
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

      unless Object.const_defined?(:V1)
        Object.const_set(:V1, Module.new)
      end
      V1::ProjectBlueprint = Class.new(Blueprinter::Base) unless V1.const_defined?(:ProjectBlueprint)
      V1::ProjectBlueprint.class_eval do
        fields :id, :name
      end

      let_class("UserBlueprint", parent: Blueprinter::Base) do
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
  end
end
