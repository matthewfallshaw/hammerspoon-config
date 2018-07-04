require 'spec.spec_helper'

describe("Expect library functions", function()
  local expect = require 'utilities.expect'

  describe("argument_to_be_in_table", function()
    it("should return nil when argument is in table", function()
      assert.is_nil(expect.argument_to_be_in_table('thing', {'thing'}))
    end)
  end)
end)
