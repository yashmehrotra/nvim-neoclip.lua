local function escape_keys(keys)
    return vim.api.nvim_replace_termcodes(keys, true, false, true)
end

local function feedkeys(keys)
    vim.api.nvim_feedkeys(escape_keys(keys), 'xmt', true)
end

local function assert_buffer_contents (expected_contents)
    return function ()
        local current_buffer = vim.fn.join(vim.api.nvim_buf_get_lines(0, 0, -1, true), '\n')
        assert.are.equal(expected_contents, current_buffer)
    end
end

local function assert_scenario(scenario)
    if scenario.initial_buffer then
        vim.api.nvim_buf_set_lines(0, 0, -1, true, vim.fn.split(scenario.initial_buffer, '\n'))
    end
    if scenario.setup then scenario.setup() end
    if scenario.feedkeys then
        for _, raw_keys in ipairs(scenario.feedkeys) do
            if type(raw_keys) == 'string' then
                feedkeys(raw_keys)
            elseif type(raw_keys) == 'function' then
                raw_keys()
            else
                if raw_keys.before then raw_keys.before() end
                feedkeys(raw_keys.keys)
                if raw_keys.after then raw_keys.after() end
            end
        end
    end
    if scenario.interlude then scenario.interlude() end
    if scenario.assert then scenario.assert() end
    if scenario.expected_buffer then
        assert_buffer_contents(scenario.expected_buffer)()
    end
end

local function unload(name)
    for pkg, _ in pairs(package.loaded) do
        if vim.fn.match(pkg, name) ~= -1 then
            package.loaded[pkg] = nil
        end
    end
end

describe("neoclip", function()
    after_each(function()
        require('neoclip.storage').clear()
        unload('neoclip')
        unload('telescope')
        vim.api.nvim_buf_set_lines(0, 0, -1, true, {})
    end)
    it("storage", function()
        assert_scenario{
            setup = function()
                require('neoclip').setup()
            end,
            initial_buffer = [[
some line
another line
multiple lines
multiple lines
multiple lines
multiple lines
some chars
a block
a block
]],
            feedkeys = {
                "jyy",
                "jyy",
                "jV3jy",
                "4jv$y",
                "j<C-v>j$",

            },
            assert = function()
                assert_equal_tables(
                    {
                        {
                            contents = {"a block", ""},
                            filetype = "",
                            regtype = "c"
                        },
                        {
                            contents = {"multiple lines", "multiple lines", "multiple lines", "some chars"},
                            filetype = "",
                            regtype = "l"
                        },
                        {
                            contents = {"multiple lines"},
                            filetype = "",
                            regtype = "l"
                        },
                        {
                            contents = {"another line"},
                            filetype = "",
                            regtype = "l"
                        },
                    },
                    require('neoclip.storage').get().yanks
                )
            end,
        }
    end)
    it("storage max", function()
        assert_scenario{
            initial_buffer = [[
a
b
c
d
]],
            setup = function()
                require('neoclip').setup({
                    history = 2,
                })
            end,
            feedkeys = {
                "jyy",
                "jyy",
                "jyy",
                "jyy",
            },
            assert = function()
                assert_equal_tables(
                    {
                        {
                            contents = {"d"},
                            filetype = "",
                            regtype = "l"
                        },
                        {
                            contents = {"c"},
                            filetype = "",
                            regtype = "l"
                        },
                    },
                    require('neoclip.storage').get().yanks
                )
            end,
        }
    end)
    it("duplicates", function()
        assert_scenario{
            initial_buffer = [[some line]],
            setup = function()
                require('neoclip').setup()
            end,
            feedkeys = {
                "yy",
                "yy",
                "Y",
            },
            assert = function()
                assert_equal_tables(
                    {
                        {
                            contents = {"some line"},
                            filetype = "",
                            regtype = "c"
                        },
                        {
                            contents = {"some line"},
                            filetype = "",
                            regtype = "l"
                        },
                    },
                    require('neoclip.storage').get().yanks
                )
            end,
        }
    end)
    it("continuous_sync push", function()
        local called = false
        assert_scenario{
            initial_buffer = [[some line]],
            setup = function()
                require('neoclip').setup({
                    enable_persistent_history = true,
                    continuous_sync = true,
                })
                -- mock the push
                require('neoclip.storage').push = function()
                    called = true
                end
            end,
            feedkeys = {
                "yy",
            },
            assert = function()
                assert(called)
            end,
        }
    end)
    it("continuous_sync pull", function()
        local called = false
        assert_scenario{
            initial_buffer = [[some line]],
            setup = function()
                require('neoclip').setup({
                    enable_persistent_history = true,
                    continuous_sync = true,
                })
                -- mock the pull
                require('neoclip.storage').pull = function()
                    called = true
                end
            end,
            feedkeys = {
                {
                    keys=[[:lua require('telescope').extensions.neoclip.neoclip()<CR>]],
                    after = function()
                        vim.wait(100, function() end)
                    end,
                },
                "<Esc><Esc>",
            },
            assert = function()
                assert(called)
            end,
        }
    end)
    it("persistent history", function()
        assert_scenario{
            initial_buffer = [[some line]],
            setup = function()
                require('neoclip').setup({
                    enable_persistent_history = true,
                    db_path = '/tmp/nvim/databases/neoclip.sqlite3',
                })
                vim.fn.system('rm /tmp/nvim/databases/neoclip.sqlite3')
            end,
            feedkeys = {"yy"},
            interlude = function()
                -- emulate closing and starting neovim
                vim.cmd('doautocmd VimLeavePre')
                unload('neoclip')
                require('neoclip.settings').get().enable_persistent_history = true
                require('neoclip.settings').get().db_path = '/tmp/nvim/databases/neoclip.sqlite3'
            end,
            assert = function()
                assert_equal_tables(
                    {
                        {
                            contents = {"some line"},
                            filetype = "",
                            regtype = "l"
                        },
                    },
                    require('neoclip.storage').get().yanks
                )
                assert(vim.fn.filereadable('/tmp/nvim/databases/neoclip.sqlite3'))
            end,
        }
    end)
    it("persistant history", function()
        assert_scenario{
            initial_buffer = [[some line]],
            setup = function()
                require('neoclip').setup({
                    enable_persistant_history = true,
                })
            end,
            assert = function()
                assert.are.equal(require('neoclip.settings').get().enable_persistent_history, true)
            end,
        }
    end)
    it("filter (whitespace)", function()
        assert_scenario{
            initial_buffer = '\nsome line\n\n\t\n',
            setup = function()
                local function is_whitespace(line)
                    return vim.fn.match(line, [[^\s*$]]) ~= -1
                end

                local function all(tbl, check)
                    for _, entry in ipairs(tbl) do
                        if not check(entry) then
                            return false
                        end
                    end
                    return true
                end

                require('neoclip').setup({
                    filter = function(data)
                        return not all(data.event.regcontents, is_whitespace)
                    end,
                })
            end,
            feedkeys = {
                "yy",
                "jyy",
                "jyy",
                "jyy",
            },
            assert = function()
                assert_equal_tables(
                    {
                        {
                            contents = {"some line"},
                            filetype = "",
                            regtype = "l"
                        },
                    },
                    require('neoclip.storage').get().yanks
                )
            end,
        }
    end)
    it("basic telescope usage", function()
        assert_scenario{
            initial_buffer = [[some line
another line]],
            feedkeys = {
                "yy",
                "jyy",
                {
                    keys=[[:lua require('telescope').extensions.neoclip.neoclip()<CR>]],
                    after = function()
                        vim.wait(100, function() end)
                    end,
                },
                "k<CR>",
                "p",
            },
            assert = function()
                assert.are.equal(vim.fn.getreg('"'), 'some line\n')
            end,
            expected_buffer = [[some line
another line
some line]],
        }
    end)
    it("paste directly", function()
        assert_scenario{
            initial_buffer = [[some line
another line]],
            feedkeys = {
                "yy",
                "jyy",
                {
                    keys=[[:lua require('telescope').extensions.neoclip.neoclip()<CR>]],
                    after = function()
                        vim.wait(100, function() end)
                    end,
                },
                "kp",
            },
            assert = function()
                assert.are.equal(vim.fn.getreg('"'), 'another line\n')
            end,
            expected_buffer = [[some line
another line
some line]],
        }
    end)
    it("set reg on paste", function()
        assert_scenario{
            setup = function()
                require('neoclip').setup({
                    on_paste = {
                        set_reg = true,
                    }
                })
            end,
            initial_buffer = [[some line
another line]],
            feedkeys = {
                "yy",
                "jyy",
                {
                    keys=[[:lua require('telescope').extensions.neoclip.neoclip()<CR>]],
                    after = function()
                        vim.wait(100, function() end)
                    end,
                },
                "kp",
            },
            assert = function()
                assert.are.equal(vim.fn.getreg('"'), 'some line\n')
            end,
            expected_buffer = [[some line
another line
some line]],
        }
    end)
    it("default register", function()
        assert_scenario{
            setup = function()
                require('neoclip').setup({
                    default_register = 'a',
                })
            end,
            initial_buffer = [[some line]],
            feedkeys = {
                "yy",
                {
                    keys=[[:lua require('telescope').extensions.neoclip.default()<CR>]],
                    after = function()
                        vim.wait(100, function() end)
                    end,
                },
                "<CR>",
            },
            assert = function()
                assert.are.equal(vim.fn.getreg('a'), 'some line\n')
            end,
        }
    end)
    it("multiple default registers", function()
        assert_scenario{
            setup = function()
                require('neoclip').setup({
                    default_register = {'a', 'b'},
                })
            end,
            initial_buffer = [[some line]],
            feedkeys = {
                "yy",
                {
                    keys=[[:lua require('telescope').extensions.neoclip.neoclip()<CR>]],
                    after = function()
                        vim.wait(100, function() end)
                    end,
                },
                "<CR>",
            },
            assert = function()
                assert.are.equal(vim.fn.getreg('a'), 'some line\n')
                assert.are.equal(vim.fn.getreg('b'), 'some line\n')
            end,
        }
    end)
    it("macro", function()
        assert_scenario{
            setup = function()
                require('neoclip').setup()
            end,
            feedkeys = {
                "qq",
                "yy",
                "q",
            },
            assert = function()
                assert_equal_tables(
                    {
                        {
                            contents = {"yy"},
                            regtype = "c"
                        },
                    },
                    require('neoclip.storage').get().macros
                )
            end,
        }
    end)
    it("macro disabled", function()
        assert_scenario{
            setup = function()
                require('neoclip').setup({
                    enable_macro_history = false,
                })
            end,
            feedkeys = {
                "qq",
                "yy",
                "q",
            },
            assert = function()
                assert.are.equal(vim.fn.getreg('q'), 'yy')
                assert_equal_tables(
                    {},
                    require('neoclip.storage').get().macros
                )
            end,
        }
    end)
    it("set reg on replay", function()
        assert_scenario{
            setup = function()
                require('neoclip').setup({
                    on_replay = {
                        set_reg = true,
                    }
                })
            end,
            initial_buffer = [[some line
another line]],
            feedkeys = {
                "qq",
                "yyp",
                "q",
                "qq",
                "j",
                "q",
                {
                    keys=[[:lua require('telescope').extensions.macroscope.default()<CR>]],
                    after = function()
                        vim.wait(100, function() end)
                    end,
                },
                "kq",
            },
            assert = function()
                assert.are.equal(vim.fn.getreg('q'), 'yyp')
            end,
            expected_buffer = [[some line
some line
another line
another line]],
        }
    end)
    it("macro default register", function()
        assert_scenario{
            setup = function()
                require('neoclip').setup({
                    default_register_macros = 'a',
                })
            end,
            initial_buffer = [[some line]],
            feedkeys = {
                "qq",
                "yy",
                "q",
                {
                    keys=[[:lua require('telescope').extensions.macroscope.macroscope()<CR>]],
                    after = function()
                        vim.wait(100, function() end)
                    end,
                },
                "<CR>",
            },
            assert = function()
                assert.are.equal(vim.fn.getreg('a'), 'yy')
            end,
        }
    end)
    it("multiple default registers", function()
        assert_scenario{
            setup = function()
                require('neoclip').setup({
                    default_register_macros = {'a', 'b'},
                })
            end,
            initial_buffer = [[some line]],
            feedkeys = {
                "qq",
                "yy",
                "q",
                {
                    keys=[[:lua require('telescope').extensions.macroscope.macroscope()<CR>]],
                    after = function()
                        vim.wait(100, function() end)
                    end,
                },
                "<CR>",
            },
            assert = function()
                assert.are.equal(vim.fn.getreg('a'), 'yy')
                assert.are.equal(vim.fn.getreg('b'), 'yy')
            end,
        }
    end)
    it("extra", function()
        assert_scenario{
            initial_buffer = [[some line
another line]],
            feedkeys = {
                "yy",
                "jyy",
                {
                    keys=[[:lua require('telescope').extensions.neoclip.neoclip({extra='a,b,c'})<CR>]],
                    after = function()
                        vim.wait(100, function() end)
                    end,
                },
                "k<CR>",
                "p",
            },
            assert = function()
                for _, reg in ipairs({'"', 'a', 'b', 'c'}) do
                    assert.are.equal(vim.fn.getreg(reg), 'some line\n')
                end
            end,
            expected_buffer = [[some line
another line
some line]],
        }
    end)
    it("keybinds", function()
        local keys = {
            telescope = {
                i = {
                    select = '<c-a>',
                    paste = '<c-b>',
                    paste_behind = '<c-c>',
                    replay = '<c-d>',
                    delete = '<c-e>',
                    edit = '<c-e>',
                    custom = {
                        ['<c-f>'] = function(opts)
                            return opts
                        end
                    },
                },
                n = {
                    select = 'a',
                    paste = 'b',
                    paste_behind = 'c',
                    replay = 'd',
                    delete = 'e',
                    edit = 'e',
                    custom = {
                        f = function(opts)
                            return opts
                        end
                    },
                },
            },
            fzf = {
                select = '<c-a>',
                paste = '<c-b>',
                paste_behind = '<c-c>',
                custom = {
                    ['<c-e>'] = function(opts)
                        return opts
                    end
                },
            },
        }

        assert_scenario{
            setup = function()
                require('neoclip').setup({
                    keys = keys,
                })
            end,
            assert = function()
                assert_equal_tables(require('neoclip.settings').get().keys, keys)
            end,
        }
    end)
    it("keybinds (deprecated)", function()
        local keys = {
            i = {
                select = '<c-a>',
            },
        }

        assert_scenario{
            setup = function()
                require('neoclip').setup({
                    keys = keys,
                })
            end,
            assert = function()
                assert.are.equal(require('neoclip.settings').get().keys.telescope.i.select, '<c-a>')
            end,
        }
    end)
    it("length limit", function()
        assert_scenario{
            setup = function()
                require('neoclip').setup({
                    length_limit = 8,
                })
            end,
            initial_buffer = [[1234
567

123456789
]],
            feedkeys = {
                "yy",
                "yj",
                "y2j",
                "3j",
                "y8l",
                "y9l",
                "yy",
            },
            assert = function()
                assert_equal_tables(
                    {
                        {
                            contents = {"12345678"},
                            filetype = "",
                            regtype = "c"
                        },
                        {
                            contents = {"1234", "567"},
                            filetype = "",
                            regtype = "l"
                        },
                        {
                            contents = {"1234"},
                            filetype = "",
                            regtype = "l"
                        },
                    },
                    require('neoclip.storage').get().yanks
                )
            end,
        }
    end)
    it("edit entry", function()
        assert_scenario{
            initial_buffer = [[This is some text
This is also some text
I like trains
Foo Bar bar foo
]],
            feedkeys = {
                -- Yank the four lines
                "yy",
                "j",
                "yy",
                "j",
                "yy",
                "j",
                "yy",
                -- Open telescope
                {
                    keys=[[:lua require('telescope').extensions.neoclip.neoclip()<CR>]],
                    after = function()
                        vim.wait(100, function() end)
                    end,
                },
                "k", -- Select second entry (should be "I like trains")
                "e", -- Edit the selected entry
                "$ciw", -- Go to end of the line and change inner word
                "aplanes", -- type "planes" in insert mode
                ":q<CR>", -- quit
                "<CR>", -- Select the entry
            },
            assert = function()
                assert_equal_tables(
                    {
                        {
                            contents = {"trains"},
                            filetype = "",
                            regtype = "c"
                        },
                        {
                            contents = {"Foo Bar bar foo"},
                            filetype = "",
                            regtype = "l"
                        },
                        {
                            contents = {"I like planes"},
                            filetype = "",
                            regtype = "l"
                        },
                        {
                            contents = {"This is also some text"},
                            filetype = "",
                            regtype = "l"
                        },
                        {
                            contents = {"This is some text"},
                            filetype = "",
                            regtype = "l"
                        }
                    },
                    require('neoclip.storage').get().yanks
                )
            end,
        }
    end)
    it("telescope stays open", function()
        assert_scenario{
            setup = function ()
                require('neoclip').setup({
                    on_select = { close_telescope = false },
                    on_paste = { close_telescope = false },
                    on_replay = { close_telescope = false },
                })
            end,
            initial_buffer = [[Some
Text
Is
Here]],
            feedkeys = {
                "jyy", -- Go down a line and yank it
                { -- Open telescope for yanks
                    keys=[[:lua require('telescope').extensions.neoclip.neoclip()<CR>]],
                    after = function()
                        vim.wait(100, function() end)
                    end,
                },
                "i<c-p>", -- Paste the current entry
                "i<c-p>", -- Paste it again (telescope should be open)
                "<ESC>", -- Close telescope
                assert_buffer_contents([[Some
Text
Text
Text
Is
Here]]),
                "qqraq", -- Record a macro that replaces a character to "a"
                "qqrbq", -- Record another macro that replaces a character to "b"
                "j$", -- Go to the end of the line below
                { -- Open telescope for macroscope
                    keys=[[:lua require('telescope').extensions.macroscope.macroscope()<CR>]],
                    after = function()
                        vim.wait(100, function() end)
                    end,
                },
                "i<c-q>", -- Replay last macro (replace with "b")
                "ki<c-q>", -- Replay first macro (replace with "a")
                "<ESC>", -- Close telescope
            },
            expected_buffer = [[Some
Text
Text
bext
Ia
Here]]
        }
    end)
end)

-- TODO why does this needs it's own thing?
describe("neoclip", function()
    after_each(function()
        require('neoclip.storage').clear()
        unload('neoclip')
        unload('telescope')
        vim.api.nvim_buf_set_lines(0, 0, -1, true, {})
    end)
    it("replay directly", function()
        assert_scenario{
            initial_buffer = [[some line
another line]],
            feedkeys = {
                "qq",
                "yyp",
                "q",
                "qq",
                "j",
                "q",
                {
                    keys=[[:lua require('telescope').extensions.macroscope.default()<CR>]],
                    after = function()
                        vim.wait(100, function() end)
                    end,
                },
                "kq",
            },
            assert = function()
                assert.are.equal(vim.fn.getreg('q'), 'j')
            end,
            expected_buffer = [[some line
some line
another line
another line]],
        }
    end)
end)
