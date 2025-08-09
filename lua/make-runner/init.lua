local M       = {}

M.bufnr       = nil
M.job_id      = nil
local link_ns = vim.api.nvim_create_namespace("msbuild_links")

function M.get_buf()
    if not M.bufnr or not vim.api.nvim_buf_is_valid(M.bufnr) then
        M.bufnr = vim.api.nvim_create_buf(true, true)
        vim.api.nvim_buf_set_name(M.bufnr, "Make Output")
        vim.api.nvim_buf_set_option(M.bufnr, "bufhidden", "hide")
        vim.api.nvim_buf_set_option(M.bufnr, "filetype", "log")
        vim.keymap.set("n", "<C-LeftMouse>", function()
            local pos = vim.fn.getmousepos()
            M.open_error_in_line(pos.line)
        end, { buffer = M.bufnr, desc = "Jump to build error" })
        vim.keymap.set("n", "<leader>g", function()
            local lnum = vim.api.nvim_win_get_cursor(0)[1]
            M.open_error_in_line(lnum)
        end, {
            buffer = M.bufnr,
            desc   = "Jump to build error under cursor",
        })
    end
    return M.bufnr
end

function M.open_win()
    local bufnr = M.get_buf()
    for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(w) == bufnr then
            vim.api.nvim_set_current_win(w)
            return w
        end
    end
    vim.cmd("botright vsplit | vertical resize 40")
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, bufnr)
    return win
end

function M.highlight()
    if not M.bufnr or not vim.api.nvim_buf_is_valid(M.bufnr) then return end
    vim.api.nvim_buf_clear_namespace(M.bufnr, link_ns, 0, -1)
    local lines = vim.api.nvim_buf_get_lines(M.bufnr, 0, -1, false)
    for i, line in ipairs(lines) do
        -- match e.g. C:\path\to\File.cpp(123,45)
        for s, e in line:gmatch("()[-%w\\:/. ]+%(%d+,%d+%)()") do
            vim.api.nvim_buf_add_highlight(M.bufnr, link_ns, "Underlined", i - 1, s - 1, e - 1)
        end
        -- match e.g. C:\CodingCool\GuentherTech\Projects\BWMERP\BWMERP\ApplicationEvents.vb:line 25
        for s, e in line:gmatch("in%s+()[-%w\\\\:/. ]-:line%s+%d+()") do
            vim.api.nvim_buf_add_highlight(M.bufnr, link_ns, "Underlined", i - 1, s - 1, e - 1)
        end
    end
end

function M.open_error_in_line(lnum)
    if not M.bufnr then
        return
    end
    local line = vim.api.nvim_buf_get_lines(
        M.bufnr, lnum - 1, lnum, false
    )[1] or ""
    local path, row, col = line:match("([^%(]+)%((%d+),(%d+)%)")
    if not path then
        path, row = line:match("in%s+(.+):line%s*(%d+)")
        col = 1
    end
    if not path then
        vim.notify("No build-error link on that line",
            vim.log.levels.WARN)
        return
    end
    local abs = vim.fn.fnamemodify(path, ":p")
    local bufnr = vim.fn.bufnr(abs, false)
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == bufnr then
            vim.api.nvim_set_current_win(win)
            vim.api.nvim_win_set_cursor(win,
                { tonumber(row), tonumber(col) - 1 })
            return
        end
    end
    if bufnr > 0 then
        vim.cmd("vsplit")
        vim.api.nvim_win_set_buf(0, bufnr)
    else
        vim.cmd("vsplit " .. vim.fn.fnameescape(abs))
    end
    vim.api.nvim_win_set_cursor(0, { tonumber(row), tonumber(col) - 1 })
end

function M.toggle()
    local bufnr = M.bufnr
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        for _, w in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_buf(w) == bufnr then
                vim.api.nvim_win_close(w, true)
                return
            end
        end
    end
    M.open_win()
end

function M.cancel()
    if not M.job_id then
        vim.notify("No build process to cancel", vim.log.levels.WARN)
        return
    end
    pcall(vim.fn.jobstop, M.job_id)
    M.job_id = nil
    vim.schedule(function()
        if M.bufnr and vim.api.nvim_buf_is_valid(M.bufnr) then
            vim.api.nvim_buf_set_lines(
                M.bufnr,
                -1,
                -1,
                false,
                { "[Process cancelled]" }
            )
        end
    end)
end

function M.run(cmd)
    local function always_scroll(bufnr)
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_buf(win) == bufnr then
                vim.api.nvim_win_call(win, function()
                    vim.cmd('normal! G')
                end)
            end
        end
    end

    if M.job_id then pcall(vim.fn.jobstop, M.job_id) end

    vim.cmd("wa")

    local is_win = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
    local argv
    if is_win then
        argv = {
            "pwsh", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-Command", "make " .. cmd,
        }
    else
        argv = { "bash", "-lc", "make " .. cmd }
    end

    M.open_win()
    vim.api.nvim_buf_set_lines(M.bufnr, 0, -1, false, {})

    M.job_id = vim.fn.jobstart(argv, {
        stdout_buffered = false,
        stderr_buffered = false,
        on_stdout = function(_, data)
            if data and #data > 0 then
                for i, line in ipairs(data) do
                    data[i] = line:gsub("\r$", "")
                end
                vim.schedule(function()
                    vim.api.nvim_buf_set_lines(M.bufnr, -1, -1, false, data)
                    M.highlight()
                    always_scroll(M.bufnr)
                end)
            end
        end,
        on_stderr = function(_, data)
            if data and #data > 0 then
                for i, line in ipairs(data) do
                    data[i] = line:gsub("\r$", "")
                end
                vim.schedule(function()
                    vim.api.nvim_buf_set_lines(M.bufnr, -1, -1, false, data)
                    M.highlight()
                    always_scroll(M.bufnr)
                end)
            end
        end,
        on_exit = function(_, code)
            vim.schedule(function()
                vim.api.nvim_buf_set_lines(
                    M.bufnr, -1, -1, false,
                    { ("[Process exited with code %d]"):format(code) }
                )
                M.highlight()
                always_scroll(M.bufnr)
            end)
        end,
    })
end

function M.trouble()
    if not M.bufnr or not vim.api.nvim_buf_is_valid(M.bufnr) then
        vim.notify("No build output buffer", vim.log.levels.WARN)
        return
    end

    local items = {}
    local lines = vim.api.nvim_buf_get_lines(M.bufnr, 0, -1, false)
    for _, line in ipairs(lines) do
        local path, r, c = line:match("([^%(]+)%((%d+),(%d+)%)")
        if path then
            local filename = vim.fn.fnamemodify(path, ":p")
            local text     = line
            local kind     = "I"
            if line:match("[Ee]rror") then
                kind = "E"
            elseif line:match("[Ww]arning") then
                kind = "W"
            end
            table.insert(items, {
                filename = filename,
                lnum     = tonumber(r),
                col      = tonumber(c),
                text     = text,
                type     = kind,
            })
        end
    end

    if #items == 0 then
        vim.notify("No errors or warnings found", vim.log.levels.INFO)
        return
    end

    -- replace quickfix list
    vim.fn.setqflist({}, "r", {
        title = "Make Output",
        items = items,
    })
    require("trouble").open("quickfix")
end

function M.setup_default()
    vim.keymap.set("n", "<leader>m", M.toggle, {
        desc = "Toggle Make Output buffer",
    })
    vim.keymap.set("n", "<leader>c", M.cancel, {
        desc = "Cancel build process",
    })
    vim.keymap.set("n", "<leader>t", M.trouble, {
        desc = "Show build errors/warnings in Trouble",
    })
end

return M
