//controllers/callerTrackerConfig.js
module.exports = {
    enabled: true,
    intervalMinutes: 10,
    mobileRegex: /^[6-9][0-9]{9}$/,
    defaultStatus: 'Pending',
    maxBatchSize: 100,
    allowedClockDifferenceMinutes: 2,
};