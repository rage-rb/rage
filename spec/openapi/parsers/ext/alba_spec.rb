# frozen_string_literal: true

require "prism"

RSpec.describe Rage::OpenAPI::Parsers::Ext::Alba do
  include_context "mocked_classes"

  subject { described_class.new(**options).parse(resource) }

  let(:options) { {} }
  let(:resource) { "UserResource" }

  context "with one attribute" do
    let_class("UserResource") do
      <<~'RUBY'
        include Alba::Resource
        attributes :id
      RUBY
    end

    it do
      is_expected.to eq({ "type" => "object", "properties" => { "id" => { "type" => "string" } } })
    end
  end

  context "with multiple attributes" do
    let_class("UserResource") do
      <<~'RUBY'
        include Alba::Resource
        attributes :id, :name, :email
      RUBY
    end

    it do
      is_expected.to eq({ "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "email" => { "type" => "string" } } })
    end
  end

  context "with block attributes" do
    let_class("UserResource") do
      <<~'RUBY'
        include Alba::Resource
        attributes :id, :name

        attribute :name_with_email do |resource|
          "#{resource.name}: #{resource.email}"
        end
      RUBY
    end

    it do
      is_expected.to eq({ "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "name_with_email" => { "type" => "string" } } })
    end
  end

  context "with method attributes" do
    let_class("UserResource") do
      <<~'RUBY'
        include Alba::Resource
        attributes :id, :name, :name_with_email

        def name_with_email(user)
          "#{user.name}: #{user.email}"
        end
      RUBY
    end

    it do
      is_expected.to eq({ "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "name_with_email" => { "type" => "string" } } })
    end
  end

  context "with proc shortcuts" do
    let_class("UserResource") do
      <<~'RUBY'
        include Alba::Resource
        attributes :id, :email
        attribute :full_name, &:name
      RUBY
    end

    it do
      is_expected.to eq({ "type" => "object", "properties" => { "id" => { "type" => "string" }, "email" => { "type" => "string" }, "full_name" => { "type" => "string" } } })
    end
  end

  context "with conditional attributes" do
    let_class("UserResource") do
      <<~'RUBY'
        include Alba::Resource
        attributes :id, :name, :email, if: proc { |user, attribute| !attribute.nil? }
      RUBY
    end

    it do
      is_expected.to eq({ "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "email" => { "type" => "string" } } })
    end
  end

  context "with prefer_object_method!" do
    let_class("UserResource") do
      <<~'RUBY'
        include Alba::Resource
        prefer_object_method!

        attributes :id, :email

        def id
        end
      RUBY
    end

    it do
      is_expected.to eq({ "type" => "object", "properties" => { "id" => { "type" => "string" }, "email" => { "type" => "string" } } })
    end
  end

  context "with a root key" do
    let_class("UserResource") do
      <<~'RUBY'
        include Alba::Resource
        root_key :user
        attributes :id, :name, :email
      RUBY
    end

    it do
      is_expected.to eq({ "type" => "object", "properties" => { "user" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "email" => { "type" => "string" } } } } })
    end

    context "with an empty resource" do
      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          root_key :user
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "user" => { "type" => "object" } } })
      end
    end

    context "with root key for collection" do
      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          root_key :user, :users
          attributes :id, :name, :email
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "user" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "email" => { "type" => "string" } } } } })
      end
    end
  end

  context "with collection_key" do
    let_class("UserResource") do
      <<~'RUBY'
        include Alba::Resource
        collection_key :id
        attributes :id, :name, :email
      RUBY
    end

    it do
      is_expected.to eq({ "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "email" => { "type" => "string" } } })
    end
  end

  context "with an empty resource" do
    let_class("UserResource")

    it do
      is_expected.to eq({ "type" => "object" })
    end
  end

  context "with a many association" do
    let_class("UserResource") do
      <<~'RUBY'
        include Alba::Resource
        attributes :id, :name
        many :articles, resource: ArticleResource
      RUBY
    end

    let_class("ArticleResource") do
      <<~'RUBY'
        include Alba::Resource
        attributes :title, :content
      RUBY
    end

    it do
      is_expected.to eq({ "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "articles" => { "type" => "array", "items" => { "type" => "object", "properties" => { "title" => { "type" => "string" }, "content" => { "type" => "string" } } } } } })
    end

    context "with an inline association" do
      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id, :email

          many :articles do
            attributes :title, :content
          end
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "id" => { "type" => "string" }, "email" => { "type" => "string" }, "articles" => { "type" => "array", "items" => { "type" => "object", "properties" => { "title" => { "type" => "string" }, "content" => { "type" => "string" } } } } } })
      end
    end

    context "with a proc argument" do
      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id, :name
          many :articles,
            proc { |articles, params, user|
              filter = params[:filter] || :odd?
              articles.select { |a| a.id.__send__(filter) && !user.banned }
            },
            resource: ArticleResource
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "articles" => { "type" => "array", "items" => { "type" => "object", "properties" => { "title" => { "type" => "string" }, "content" => { "type" => "string" } } } } } })
      end
    end

    context "with a key option" do
      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id, :name
          many :articles, key: "my_articles", resource: ArticleResource
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "my_articles" => { "type" => "array", "items" => { "type" => "object", "properties" => { "title" => { "type" => "string" }, "content" => { "type" => "string" } } } } } })
      end
    end

    context "with a proc resource" do
      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id, :name
          many :articles, resource: ->(article) { article.with_comment? ? ArticleResource : ArticleResource }
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "articles" => { "type" => "array", "items" => { "type" => "object" } } } })
      end
    end

    context "with params" do
      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id, :name
          many :articles, resource: ArticleResource, params: { expose_comments: false }
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "articles" => { "type" => "array", "items" => { "type" => "object", "properties" => { "title" => { "type" => "string" }, "content" => { "type" => "string" } } } } } })
      end
    end

    context "with multiple associations" do
      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id, :name
          many :articles, resource: ArticleResource
          one :avatar, resource: AvatarResource
        RUBY
      end

      let_class("AvatarResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :url, :caption
        RUBY
      end

      let_class("ArticleResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :title, :body
          many :comments, resource: CommentResource
        RUBY
      end

      let_class("CommentResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :author, :content
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "articles" => { "type" => "array", "items" => { "type" => "object", "properties" => { "title" => { "type" => "string" }, "body" => { "type" => "string" }, "comments" => { "type" => "array", "items" => { "type" => "object", "properties" => { "author" => { "type" => "string" }, "content" => { "type" => "string" } } } } } } }, "avatar" => { "type" => "object", "properties" => { "url" => { "type" => "string" }, "caption" => { "type" => "string" } } } } })
      end
    end

    context "with the association inside a nested attribute" do
      let_class("ArticleResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :title, :body
        RUBY
      end

      let_class("CommentResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :author, :content
        RUBY
      end

      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id, :name

          nested_attribute :relationships do
            many :articles, resource: ArticleResource
            many :comments, resource: CommentResource
          end
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "relationships" => { "type" => "object", "properties" => { "articles" => { "type" => "array", "items" => { "type" => "object", "properties" => { "title" => { "type" => "string" }, "body" => { "type" => "string" } } } }, "comments" => { "type" => "array", "items" => { "type" => "object", "properties" => { "author" => { "type" => "string" }, "content" => { "type" => "string" } } } } } } } })
      end
    end

    context "with root_key in the association" do
      let_class("ArticleResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :title, :content
          root_key :article, :articles
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "articles" => { "type" => "array", "items" => { "type" => "object", "properties" => { "title" => { "type" => "string" }, "content" => { "type" => "string" } } } } } })
      end
    end

    context "with root_key and metadata in the association" do
      let_class("ArticleResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :title, :content
          root_key :article, :articles

          meta do
            { created_at: object.created_at }
          end
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "articles" => { "type" => "array", "items" => { "type" => "object", "properties" => { "title" => { "type" => "string" }, "content" => { "type" => "string" } } } } } })
      end
    end
  end

  context "with a has_one association" do
    let_class("UserResource") do
      <<~'RUBY'
        include Alba::Resource
        attributes :id, :name
        has_one :article, resource: ArticleResource
      RUBY
    end

    let_class("ArticleResource") do
      <<~'RUBY'
        include Alba::Resource
        attributes :title, :body
      RUBY
    end

    it do
      is_expected.to eq({ "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "article" => { "type" => "object", "properties" => { "title" => { "type" => "string" }, "body" => { "type" => "string" } } } } })
    end

    context "with a key option" do
      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id, :name
          has_one :article, key: "my_article", resource: ArticleResource
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "my_article" => { "type" => "object", "properties" => { "title" => { "type" => "string" }, "body" => { "type" => "string" } } } } })
      end
    end

    context "with a proc resource" do
      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id, :name
          has_one :article, resource: ->(article) { ArticleResource }
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "article" => { "type" => "object" } } })
      end
    end
  end

  context "with nested attributes" do
    let_class("UserResource") do
      <<~'RUBY'
        include Alba::Resource
        root_key :user
        attributes :id

        nested_attribute :address do
          attributes :city, :zipcode
        end
      RUBY
    end

    it do
      is_expected.to eq({ "type" => "object", "properties" => { "user" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "address" => { "type" => "object", "properties" => { "city" => { "type" => "string" }, "zipcode" => { "type" => "string" } } } } } } })
    end

    context "with deep nesting" do
      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          root_key :user
          attributes :id

          nested :address do
            nested :geo do
              attribute :id { 42 }
              attributes :lat, :lng
            end

            attributes :city, :zipcode
          end
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "user" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "address" => { "type" => "object", "properties" => { "geo" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "lat" => { "type" => "string" }, "lng" => { "type" => "string" } } }, "city" => { "type" => "string" }, "zipcode" => { "type" => "string" } } } } } } })
      end
    end
  end

  context "with inheritance" do
    let_class("BaseResource") do
      <<~'RUBY'
        include Alba::Resource
        attributes :id, :created_at
      RUBY
    end

    let_class("UserResource", parent: mocked_classes.BaseResource) do
      <<~'RUBY'
        attributes :name, :email
      RUBY
    end

    it do
      is_expected.to eq({ "type" => "object", "properties" => { "id" => { "type" => "string" }, "created_at" => { "type" => "string" }, "name" => { "type" => "string" }, "email" => { "type" => "string" } } })
    end

    context "with a root key" do
      let_class("BaseResource") do
        <<~'RUBY'
          include Alba::Resource
          root_key :data
          attributes :id, :created_at
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "data" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "created_at" => { "type" => "string" }, "name" => { "type" => "string" }, "email" => { "type" => "string" } } } } })
      end
    end

    context "with nested attributes and associations" do
      let_class("AddressResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :street, :postal_code
        RUBY
      end

      let_class("MinimalUserResource") do
        <<~'RUBY'
          include Alba::Resource
          root_key :user

          attributes :id, :name, :email
          one :address, resource: AddressResource

          nested_attribute :avatar do
            attribute :url
          end
        RUBY
      end

      let_class("UserResource", parent: mocked_classes.MinimalUserResource) do
        <<~'RUBY'
          many :comments do
            attribute :content, :created_at
          end
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "user" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "email" => { "type" => "string" }, "address" => { "type" => "object", "properties" => { "street" => { "type" => "string" }, "postal_code" => { "type" => "string" } } }, "avatar" => { "type" => "object", "properties" => { "url" => { "type" => "string" } } }, "comments" => { "type" => "array", "items" => { "type" => "object", "properties" => { "content" => { "type" => "string" }, "created_at" => { "type" => "string" } } } } } } } })
      end
    end

    context "with metadata" do
      let_class("BaseResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id, :created_at
          root_key :data

          meta do
            { session_id: Current.session_id }
          end
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "data" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "created_at" => { "type" => "string" }, "name" => { "type" => "string" }, "email" => { "type" => "string" } } }, "meta" => { "type" => "object", "properties" => { "session_id" => { "type" => "string" } } } } })
      end
    end
  end

  context "with key transformation" do
    before do
      stub_const("Alba", double(inflector: double))
      allow(Alba.inflector).to receive(:camelize) { |str| str.gsub("_", "+").capitalize }
    end

    let_class("UserResource") do
      <<~'RUBY'
        include Alba::Resource
        attributes :id, :first_name, :last_name
        transform_keys :camel
      RUBY
    end

    it do
      is_expected.to eq({ "type" => "object", "properties" => { "Id" => { "type" => "string" }, "First+name" => { "type" => "string" }, "Last+name" => { "type" => "string" } } })
    end

    context "with associations" do
      let_class("CommentResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :content, :is_edited
          transform_keys :camel
        RUBY
      end

      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id, :first_name, :last_name
          many :comments, resource: CommentResource
          transform_keys :camel
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "Id" => { "type" => "string" }, "First+name" => { "type" => "string" }, "Last+name" => { "type" => "string" }, "Comments" => { "type" => "array", "items" => { "type" => "object", "properties" => { "Content" => { "type" => "string" }, "Is+edited" => { "type" => "string" } } } } } })
      end
    end

    context "with collection_key" do
      let(:resource) { "[UserResource]" }

      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id, :first_name, :last_name
          transform_keys :camel
          collection_key :id
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "additionalProperties" => { "type" => "object", "properties" => { "Id" => { "type" => "string" }, "First+name" => { "type" => "string" }, "Last+name" => { "type" => "string" } } } })
      end
    end

    context "with inheritance" do
      let_class("BaseResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id
          transform_keys :camel
        RUBY
      end

      let_class("UserResource", parent: mocked_classes.BaseResource) do
        <<~'RUBY'
          include Alba::Resource
          attributes :first_name, :last_name
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "Id" => { "type" => "string" }, "First+name" => { "type" => "string" }, "Last+name" => { "type" => "string" } } })
      end

      context "with disabled transformation" do
        let_class("BaseResource") do
          <<~'RUBY'
            include Alba::Resource
            attributes :id
            transform_keys :camel
          RUBY
        end

        let_class("UserResource", parent: mocked_classes.BaseResource) do
          <<~'RUBY'
            include Alba::Resource
            attributes :first_name, :last_name
            transform_keys :none
          RUBY
        end

        it do
          is_expected.to eq({ "type" => "object", "properties" => { "id" => { "type" => "string" }, "first_name" => { "type" => "string" }, "last_name" => { "type" => "string" } } })
        end
      end
    end

    context "with no inflector" do
      before do
        stub_const("Alba", double(inflector: nil))
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "id" => { "type" => "string" }, "first_name" => { "type" => "string" }, "last_name" => { "type" => "string" } } })
      end
    end
  end

  context "with metadata" do
    let_class("UserResource") do
      <<~'RUBY'
        include Alba::Resource
        attributes :id, :name
        root_key :user

        meta do
          if object.is_a?(Enumerable)
            { size: object.size }
          else
            { foo: :bar }
          end
        end
      RUBY
    end

    it do
      is_expected.to eq({ "type" => "object", "properties" => { "user" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" } } }, "meta" => { "type" => "object", "properties" => { "size" => { "type" => "string" } } } } })
    end

    context "with a custom key" do
      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id, :name
          root_key :user

          meta :my_meta do
            { created_at: object.created_at }
          end
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "user" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" } } }, "my_meta" => { "type" => "object", "properties" => { "created_at" => { "type" => "string" } } } } })
      end
    end

    context "with a custom key and no data" do
      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id, :name
          root_key :user
          meta :my_meta
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "user" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" } } }, "my_meta" => { "type" => "object" } } })
      end
    end

    context "with no key" do
      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id, :name
          root_key :user
          meta nil
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "user" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" } } } } })
      end
    end

    context "with custom class" do
      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id, :name
          root_key :user

          meta do
            MetaService.new(object).call
          end
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "user" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" } } }, "meta" => { "type" => "object" } } })
      end
    end

    context "with no root key" do
      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id, :name

          meta :my_meta do
            { created_at: object.created_at }
          end
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" } } })
      end
    end

    context "with no root key and collection" do
      let(:resource) { "[UserResource]" }

      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id, :name

          meta :my_meta do
            { created_at: object.created_at }
          end
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "array", "items" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" } } } })
      end

      context "with collection_key" do
        let_class("UserResource") do
          <<~'RUBY'
            include Alba::Resource
            attributes :id, :name
            collection_key :id

            meta :my_meta do
              { created_at: object.created_at }
            end
          RUBY
        end

        it do
          is_expected.to eq({ "type" => "object", "additionalProperties" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" } } } })
        end
      end
    end
  end

  context "with types" do
    let_class("UserResource") do
      <<~'RUBY'
        include Alba::Resource
        attributes :name, id: [String, true], age: [Integer, true], bio: String, admin: [:Boolean, true], salary: Float, created_at: [String, ->(object) { object.strftime('%F') }]
      RUBY
    end

    it do
      is_expected.to eq({ "type" => "object", "properties" => { "name" => { "type" => "string" }, "id" => { "type" => "string" }, "age" => { "type" => "integer" }, "bio" => { "type" => "string" }, "admin" => { "type" => "boolean" }, "salary" => { "type" => "number", "format" => "float" }, "created_at" => { "type" => "string" } } })
    end

    context "with nested attributes" do
      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource

          nested_attribute :data do
            attributes :name, id: Integer, admin: :Boolean, salary: Float
          end
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "data" => { "type" => "object", "properties" => { "name" => { "type" => "string" }, "id" => { "type" => "integer" }, "admin" => { "type" => "boolean" }, "salary" => { "type" => "number", "format" => "float" } } } } })
      end
    end

    context "with dates" do
      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes created_at: DateTime, dob: Date
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "created_at" => { "type" => "string", "format" => "date-time" }, "dob" => { "type" => "string", "format" => "date" } } })
      end
    end
  end

  context "with automatic resource inference" do
    before do
      stub_const("Alba", double(inflector: double))
      allow(Alba.inflector).to receive(:classify) do |str|
        case str
        when "articles"
          "Article"
        when "avatar"
          "Avatar"
        end
      end
    end

    let_class("ArticleResource") do
      <<~'RUBY'
        include Alba::Resource
        attributes :title, :body
      RUBY
    end

    let_class("AvatarResource") do
      <<~'RUBY'
        include Alba::Resource
        attributes :url
      RUBY
    end

    let_class("UserResource") do
      <<~'RUBY'
        include Alba::Resource
        attributes :id, :name
        many :articles
        one :avatar
      RUBY
    end

    it do
      is_expected.to eq({ "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "articles" => { "type" => "array", "items" => { "type" => "object", "properties" => { "title" => { "type" => "string" }, "body" => { "type" => "string" } } } }, "avatar" => { "type" => "object", "properties" => { "url" => { "type" => "string" } } } } })
    end

    context "with no inflector" do
      before do
        stub_const("Alba", double(inflector: nil))
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "articles" => { "type" => "array", "items" => { "type" => "object" } }, "avatar" => { "type" => "object" } } })
      end
    end
  end

  context "with collection" do
    let(:resource) { "[UserResource]" }

    let_class("UserResource") do
      <<~'RUBY'
        include Alba::Resource
        attributes :id, :name, :email
      RUBY
    end

    it do
      is_expected.to eq({ "type" => "array", "items" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "email" => { "type" => "string" } } } })
    end

    context "with a has_many association" do
      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id, :name
          has_many :articles, resource: ArticleResource
        RUBY
      end

      let_class("ArticleResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :title, :content
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "array", "items" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "articles" => { "type" => "array", "items" => { "type" => "object", "properties" => { "title" => { "type" => "string" }, "content" => { "type" => "string" } } } } } } })
      end
    end

    context "with a has_one association" do
      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id, :name
          has_one :article, resource: ArticleResource
        RUBY
      end

      let_class("ArticleResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :title, :content
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "array", "items" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "article" => { "type" => "object", "properties" => { "title" => { "type" => "string" }, "content" => { "type" => "string" } } } } } })
      end
    end

    context "with inline has_many association" do
      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id, :name

          has_many :articles do
            attributes :title, :content
          end
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "array", "items" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "articles" => { "type" => "array", "items" => { "type" => "object", "properties" => { "title" => { "type" => "string" }, "content" => { "type" => "string" } } } } } } })
      end
    end

    context "with inline has_one association" do
      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id, :name

          has_one :article do
            attributes :title, :content
          end
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "array", "items" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "article" => { "type" => "object", "properties" => { "title" => { "type" => "string" }, "content" => { "type" => "string" } } } } } })
      end
    end

    context "with root key" do
      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id, :name, :email
          root_key :user
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "array", "items" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "email" => { "type" => "string" } } } })
      end

      context "with metadata" do
        let_class("UserResource") do
          <<~'RUBY'
            include Alba::Resource
            attributes :id, :name, :email
            root_key :user

            meta do
              { session_id: Current.session_id }
            end
          RUBY
        end

        it do
          is_expected.to eq({ "type" => "array", "items" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "email" => { "type" => "string" } } } })
        end
      end
    end

    context "with root key for collection" do
      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id, :name, :email
          root_key :user, :all_users
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "all_users" => { "type" => "array", "items" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "email" => { "type" => "string" } } } } } })
      end

      context "with metadata" do
        let_class("UserResource") do
          <<~'RUBY'
            include Alba::Resource
            attributes :id, :name, :email
            root_key :user, :all_users

            meta do
              { session_id: Current.session_id }
            end
          RUBY
        end

        it do
          is_expected.to eq({ "type" => "object", "properties" => { "all_users" => { "type" => "array", "items" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "email" => { "type" => "string" } } } }, "meta" => { "type" => "object", "properties" => { "session_id" => { "type" => "string" } } } } })
        end
      end
    end

    context "with root key for collection and collection_key" do
      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id, :name, :email
          root_key :user, :all_users
          collection_key :id
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "all_users" => { "type" => "object", "additionalProperties" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "email" => { "type" => "string" } } } } } })
      end

      context "with metadata" do
        let_class("UserResource") do
          <<~'RUBY'
            include Alba::Resource
            attributes :id, :name, :email
            root_key :user, :all_users
            collection_key :id

            meta do
              { session_id: Current.session_id }
            end
          RUBY
        end

        it do
          is_expected.to eq({ "type" => "object", "properties" => { "all_users" => { "type" => "object", "additionalProperties" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "email" => { "type" => "string" } } } }, "meta" => { "type" => "object", "properties" => { "session_id" => { "type" => "string" } } } } })
        end
      end
    end
  end

  context "with collection_key" do
    let(:resource) { "[UserResource]" }

    let_class("UserResource") do
      <<~'RUBY'
        include Alba::Resource
        collection_key :id
        attributes :id, :name, :email
      RUBY
    end

    it do
      is_expected.to eq({ "type" => "object", "additionalProperties" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "email" => { "type" => "string" } } } })
    end

    context "with a has_many association" do
      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          collection_key :id

          attributes :id, :name
          has_many :articles, resource: ArticleResource
        RUBY
      end

      let_class("ArticleResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :title, :content
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "additionalProperties" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "articles" => { "type" => "array", "items" => { "type" => "object", "properties" => { "title" => { "type" => "string" }, "content" => { "type" => "string" } } } } } } })
      end

      context "with collection_key in the association" do
        let_class("ArticleResource") do
          <<~'RUBY'
            include Alba::Resource
            collection_key :title
            attributes :title, :content
          RUBY
        end

        it do
          is_expected.to eq({ "type" => "object", "additionalProperties" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "articles" => { "type" => "object", "additionalProperties" => { "type" => "object", "properties" => { "title" => { "type" => "string" }, "content" => { "type" => "string" } } } } } } })
        end
      end

      context "with collection_key in parent" do
        let_class("BaseResource") do
          <<~'RUBY'
            include Alba::Resource
            collection_key :id
          RUBY
        end

        let_class("UserResource", parent: mocked_classes.BaseResource) do
          <<~'RUBY'
            attributes :id, :name
            has_many :articles, resource: ArticleResource
          RUBY
        end

        let_class("ArticleResource", parent: mocked_classes.BaseResource) do
          <<~'RUBY'
            attributes :title, :content
          RUBY
        end

        it do
          is_expected.to eq({ "type" => "object", "additionalProperties" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "articles" => { "type" => "object", "additionalProperties" => { "type" => "object", "properties" => { "title" => { "type" => "string" }, "content" => { "type" => "string" } } } } } } })
        end
      end
    end

    context "with a has_one association" do
      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          collection_key :id

          attributes :id, :name
          has_one :article, resource: ArticleResource
        RUBY
      end

      let_class("ArticleResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :title, :content
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "additionalProperties" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "article" => { "type" => "object", "properties" => { "title" => { "type" => "string" }, "content" => { "type" => "string" } } } } } })
      end
    end

    xcontext "with an inline has_many association" do
      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id, :name

          has_one :articles do
            collection_key :title
            attributes :title, :content
          end
        RUBY
      end

      it do
        is_expected.to eq({})
      end
    end

    context "with an empty resource" do
      let_class("UserResource") do
        <<~'RUBY'
          include Alba::Resource
          collection_key :id
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "additionalProperties" => { "type" => "object" } })
      end
    end
  end

  context "with root_key!" do
    before do
      stub_const("Alba", double(inflector: double))
      allow(Alba.inflector).to receive(:demodulize) { |str| str.delete_prefix("Api::V1") }
      allow(Alba.inflector).to receive(:underscore) { |str| str.downcase }
      allow(Alba.inflector).to receive(:pluralize) { |str| "#{str}s" }
    end

    let_class("UserResource") do
      <<~'RUBY'
        include Alba::Resource
        attributes :id, :name
        root_key!
      RUBY
    end

    it do
      is_expected.to eq({ "type" => "object", "properties" => { "user" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" } } } } })
    end

    context "with namespace" do
      let(:resource) { "Api::V1::UserResource" }

      let_class("Api::V1::UserResource") do
        <<~'RUBY'
          include Alba::Resource
          attributes :id, :name
          root_key!
        RUBY
      end

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "user" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" } } } } })
      end
    end

    context "with collection" do
      let(:resource) { "[UserResource]" }

      it do
        is_expected.to eq({ "type" => "object", "properties" => { "users" => { "type" => "array", "items" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" } } } } } })
      end

      context "with collection_key" do
        let_class("UserResource") do
          <<~'RUBY'
            include Alba::Resource
            attributes :id, :name
            collection_key :id
            root_key!
          RUBY
        end

        it do
          is_expected.to eq({ "type" => "object", "properties" => { "users" => { "type" => "object", "additionalProperties" => { "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" } } } } } })
        end
      end
    end
  end

  context "with namespaced associations" do
    let(:resource) { "Api::V3::UserResource" }
    let(:namespace) { double }
    let(:options) { { namespace: } }

    before do
      stub_const("Alba", double(inflector: double))
      allow(Alba.inflector).to receive(:classify).with("articles").and_return("Article")
    end

    let_class("ArticleResource") do
      <<~'RUBY'
        include Alba::Resource
        attributes :title, :content
      RUBY
    end

    let_class("Api::V3::ArticleResource") do
      <<~'RUBY'
        include Alba::Resource
        attributes :v3_title, :v3_content
      RUBY
    end

    let_class("Api::V3::UserResource") do
      <<~'RUBY'
        include Alba::Resource
        attributes :id, :name
        has_many :articles
      RUBY
    end

    it do
      allow(namespace).to receive(:const_get).with("Api::V3::UserResource").and_return(Object.const_get("Api::V3::UserResource"))
      allow(namespace).to receive(:const_get).with("ArticleResource").and_return(Object.const_get("Api::V3::ArticleResource"))

      is_expected.to eq({ "type" => "object", "properties" => { "id" => { "type" => "string" }, "name" => { "type" => "string" }, "articles" => { "type" => "array", "items" => { "type" => "object", "properties" => { "v3_title" => { "type" => "string" }, "v3_content" => { "type" => "string" } } } } } })
    end
  end
end
