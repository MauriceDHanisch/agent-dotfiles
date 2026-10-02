import type { Register } from 'claude-code'

type Fs = { fs: { write: (path: string, text: string) => Promise<void> } }

let seen: { models: Record<string, string>; efforts: Record<string, string> } = { models: {}, efforts: {} }
let sessionId = ''
let viewedId: string | undefined
let lastView: string | undefined

const short = (model: string) => model.replace(/^claude-/, '').replace(/-\d.*$/, '')
const pretty = (model: string) => {
  const [name = '', ...version] = model.replace(/^claude-/, '').replace(/-\d{8}$/, '').split('-')
  return `${name.charAt(0).toUpperCase()}${name.slice(1)} ${version.join('.')}`.trim()
}
const seenFile = () => `/tmp/claude-agent-seen-${sessionId}.json`
const saveSeen = ($: Fs) => (sessionId ? $.fs.write(seenFile(), JSON.stringify(seen)) : undefined)

const writeView = async ($: Fs) => {
  const model = viewedId && seen.models[viewedId]
  const view = model ? `${pretty(model)}\t${seen.efforts[viewedId!] ?? ''}` : ''
  if (sessionId && view !== lastView) await $.fs.write(`/tmp/claude-view-${sessionId}`, (lastView = view))
}

export const register: Register = on => {
  on('agent.spawn', async ($, e, next) => {
    const started = await next(e)
    if (started.agentId) {
      seen.models[started.agentId] = started.model
      await saveSeen($)
    }
    return started
  })

  on('classic.PostToolUse', async ($, e, next) => {
    if (e.agent_id && e.effort && seen.efforts[e.agent_id] !== e.effort.level) {
      seen.efforts[e.agent_id] = e.effort.level
      await saveSeen($)
    }
    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    viewedId = e.props.view.agentId
    await writeView($)
    return next(e)
  })

  on('session.start', async ($, e, next) => {
    const started = await next(e)
    sessionId = await $.session.id()
    seen = await $.fs.read(seenFile()).then(JSON.parse, () => seen)
    let lastAgents: string | undefined
    $.clock.every(1000, async () => {
      const counts: Record<string, number> = {}
      for (const a of await $.agent.list()) {
        const model = seen.models[a.id]
        if (a.status === 'running' && model) counts[short(model)] = (counts[short(model)] ?? 0) + 1
      }
      const agents = Object.entries(counts).sort().map(([m, n]) => `${m} x${n}`).join(' ')
      if (agents !== lastAgents) await $.fs.write(`/tmp/claude-agents-${sessionId}`, (lastAgents = agents))
      await writeView($)
    })
    return started
  })
}
