import assert from 'node:assert/strict'
import { test } from 'node:test'
import { parseRobots, robotsAllows } from '../src/http.ts'

test('robots.txt: our group beats *, longest rule wins', () => {
  const txt = `User-agent: *\nDisallow: /\n\nUser-agent: PlayscribeBot\nDisallow: /private\nAllow: /private/news\n`
  const rules = parseRobots(txt)
  assert.equal(robotsAllows(rules, '/news'), true)
  assert.equal(robotsAllows(rules, '/private/x'), false)
  assert.equal(robotsAllows(rules, '/private/news/1'), true)
  assert.equal(robotsAllows(parseRobots('User-agent: *\nDisallow: /'), '/feed'), false)
  assert.equal(robotsAllows(parseRobots(''), '/feed'), true)
})
