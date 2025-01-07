# frozen_string_literal: true

##
# Collect all global comments or comments attached to methods in a class.
# At this point we don't care whether these are Rage OpenAPI comments or not.
#
class Rage::OpenAPI::Collector < Prism::Visitor
  # @param comments [Array<Prism::InlineComment>]
  def initialize(comments)
    @comments = comments.dup
    @method_comments = {}
  end

  def dangling_comments
    @comments
  end

  def method_comments(method_name)
    @method_comments[method_name.to_s]
  end

  def visit_def_node(node)
    method_comments = []
    start_line = node.location.start_line - 1

    loop do
      comment_i = @comments.find_index { |comment| comment.location.start_line == start_line }
      if comment_i
        comment = @comments.delete_at(comment_i)
        method_comments << comment
        start_line -= 1
      end

      break unless comment
    end

    @method_comments[node.name.to_s] = method_comments.reverse

    # reject comments inside methods
    @comments.reject! do |comment|
      comment.location.start_line >= node.location.start_line && comment.location.start_line <= node.location.end_line
    end
  end
end
