module ImmutableRecord
  extend ActiveSupport::Concern

  included do
    before_update :prevent_mutation
    before_destroy :prevent_mutation
  end

  private

  def prevent_mutation
    raise ActiveRecord::ReadOnlyRecord, "#{self.class.name} records are immutable"
  end
end
