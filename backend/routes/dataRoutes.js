//routes/dataRoutes.js
const express = require("express");
const dataController = require("../controllers/dataController");

const router = express.Router();

router.get("/callerTracker/config", dataController.getCallerTrackerConfig);
router.post("/syncCallerTracker", dataController.syncCallerTracker);

module.exports = router;