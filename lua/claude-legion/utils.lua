local M = {}

function M.run(cmd)
  local output = vim.fn.system(cmd)
  return vim.v.shell_error == 0, vim.trim(output)
end

function M.run_async(cmd)
  vim.fn.jobstart(cmd, { detach = true })
end

return M
