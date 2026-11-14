// Test-only numerical oracle: execute the retained TypeScript core with Node 24+.
import { registerHooks } from 'node:module';
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier.startsWith('.') && context.parentURL) {
      const candidate = new URL(`${specifier}.ts`, context.parentURL);
      if (existsSync(fileURLToPath(candidate))) {
        return nextResolve(candidate.href, context);
      }
    }
    return nextResolve(specifier, context);
  },
});

const { resampleIcon } = await import('../src/core/resample.ts');
const { buildPlan } = await import('../src/core/plan.ts');
const { allocOutputs, interpPolar } = await import('../src/core/interpolate.ts');
const { Spring, SPRING_PRESETS } = await import('../src/core/spring.ts');

const pairs = [
  ['menu-close', 'M4 6h16M4 12h16M4 18h16', 'M18 6 6 18M6 6l12 12'],
  // Use the original Lucide ordering: the whole pair has a unique rigid frame.
  // Reversing only the chevron creates a symmetric +/-90 shaft tie instead.
  ['right-down', 'M5 12h14M12 5l7 7-7 7', 'M12 5v14M19 12l-7 7-7-7'],
  ['plus-close', 'M12 4v16M4 12h16', 'M18 6 6 18M6 6l12 12'],
  ['close-check', 'M18 6 6 18M6 6l12 12', 'M20 6 9 17l-5-5'],
  ['circle-square', 'M22 12a10 10 0 1 1-20 0 10 10 0 1 1 20 0z', 'M2 2h20v20H2z'],
  ['square-diamond', 'M2 2h20v20H2z', 'M12 2l10 10-10 10L2 12z'],
].map(([name, from, to]) => {
  const plan = buildPlan(resampleIcon(from), resampleIcon(to));
  const output = allocOutputs(plan);
  const frames = [0, 0.25, 0.5, 0.75, 1].map((t) => {
    interpPolar(plan, t, output);
    return { t, points: output.map((cloud) => Array.from(cloud)) };
  });
  return { name, from, to, items: plan.items.length, angles: plan.items.map((item) => item.theta), frames };
});

const springs = Object.entries(SPRING_PRESETS).map(([name, { k, c }]) => {
  const spring = new Spring();
  spring.config(k, c);
  spring.start();
  const states = Array.from({ length: 24 }, (_, i) => {
    if (i === 7) spring.start();
    const dt = [0, 1 / 120, 1 / 60, 1 / 30, 0.064][i % 5];
    const settled = spring.step(dt);
    return { dt, x: spring.x, v: spring.v, settled };
  });
  return { name, k, c, states };
});

const output = resolve('.dart_tool/upstream-fixtures.json');
mkdirSync(dirname(output), { recursive: true });
writeFileSync(output, `${JSON.stringify({ schema_version: 1, pairs, springs })}\n`);
console.log(`Exported ${pairs.length} reference pairs and ${springs.length} springs to ${output}`);
