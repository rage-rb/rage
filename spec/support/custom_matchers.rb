# define opposite to a_hash_including matcher
RSpec::Matchers.matcher :a_hash_excluding_keys do |*excluded_keys|
  match do |actual|
    excluded_keys.flatten.none? { |key| actual.key?(key) }
  end

  failure_message do |actual|
    present_keys = excluded_keys.flatten.select { |key| actual.key?(key) }
    "expected hash not to include keys: #{present_keys.join(", ")}, but found them"
  end

  failure_message_when_negated do |actual|
    "expected hash to include at least one of the keys: #{excluded_keys.flatten.join(", ")}"
  end
end
