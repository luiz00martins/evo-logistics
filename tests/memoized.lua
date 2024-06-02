local ut = require("cc-ut")

local describe = ut.describe

local Memoized = require('/logos-library.utils.memoized').Memoized

local test_module = function()
  describe('Memoized Module', function(test)
    test("Testing return", function(expect)
      local fn1 = Memoized:new {
        name = 'fn1',
        fn = function(v)
          return 'test'..v
        end,
      }

      expect(fn1('')).toBe('test')
      expect(fn1(' abc')).toBe('test abc')
    end)

    test("Testing autosave", function(expect)
      local path = '/logos-library/data/memoized/test_autosave.cache'
      local test_autosave = Memoized:new {
        name = 'test_autosave',
        auto_save = true,
        path = path,
        fn = function(v)
          return 'test'..v
        end,
      }

      expect(test_autosave('')).toBe('test')
      expect(test_autosave(' abc')).toBe('test abc')
      expect(test_autosave(' 123')).toBe('test 123')

      local old_cache = test_autosave.cache
      local file = fs.open(path, 'r')
      local data = file.readAll()
      file.close()
      fs.delete(path)
      local new_cache = textutils.unserialize(data)
      expect(old_cache).toEqual(new_cache)
    end)
  end)
end

return {
	test_module = test_module,
}