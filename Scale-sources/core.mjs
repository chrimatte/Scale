export function parseLine(line) {
  const measurement = line.match(/Measurement: ([\d.]+) kg/);
  if (measurement) return { type: 'measurement', weight: Number(measurement[1]) };
  const fat = line.match(/bodyFatPercent: ([\d.]+)/);
  if (fat) return { type: 'fat', bodyFat: Number(fat[1]) };
  if (line.includes('wellness updated for')) return { type: 'uploaded', date: line.match(/updated for (\d{4}-\d{2}-\d{2})/)?.[1] };
  if (line.includes('broadcast-only')) return { type: 'status', stage: 'ready', message: 'Scale found. Step on barefoot and stand still.' };
  if (line.includes('Listening for broadcast') || line.includes('Connected to')) return { type: 'status', stage: 'ready', message: 'Step on the scale and wait for the result.' };
  if (line.includes('Exporting to:')) return { type: 'status', stage: 'uploading', message: 'Uploading to Intervals.icu…' };
  return null;
}
export function verifyReading(actual, weight, bodyFat, estimate) {
  if (!Number.isFinite(weight) || typeof actual.weight !== 'number' || Math.abs(actual.weight - weight) > 0.011) return false;
  return !estimate || (typeof bodyFat === 'number' && typeof actual.bodyFat === 'number' && Math.abs(actual.bodyFat - Math.round(bodyFat * 10) / 10) < 0.011);
}
export function dayInZone(timeZone, date = new Date()) {
  const parts = new Intl.DateTimeFormat('en-US', {timeZone, year:'numeric', month:'2-digit', day:'2-digit'}).formatToParts(date);
  const get = t => parts.find(p => p.type === t).value;
  return `${get('year')}-${get('month')}-${get('day')}`;
}
