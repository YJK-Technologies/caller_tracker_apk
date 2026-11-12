//controllers/dataController.js
const sql = require("mssql");
const connection = require("../connection/connection");
const callerTrackerConfig = require("./callerTrackerConfig");

const normalizeMobile = (number) => {
  let value = String(number || "").replace(/\D/g, "");
  if (value.length === 12 && value.startsWith("91")) {
    value = value.substring(2);
  } else if (value.length === 11 && value.startsWith("0")) {
    value = value.substring(1);
  }
  return value;
};

// GET /callerTracker/config
const getCallerTrackerConfig = async (req, res) => {
  console.log("==================================");
  console.log("CALLER TRACKER CONFIG API CALLED");
  console.log("Time:", new Date().toISOString());
  console.log("IP:", req.ip);
  console.log("==================================");

  return res.status(200).json({
    success: true,
    config: {
      enabled: callerTrackerConfig.enabled,
      intervalMinutes: callerTrackerConfig.intervalMinutes,
      maxBatchSize: callerTrackerConfig.maxBatchSize,
    },
  });
};

// POST /syncCallerTracker
const syncCallerTracker = async (req, res) => {

  let transaction;

  try {
    const { MobileNo, company_code, location_code, created_by, calls } = req.body || {};

    if (!callerTrackerConfig.enabled) {
      return res.status(403).json({
        success: false,
        message: "Caller Tracker sync is disabled",
      });
    }

    
    if (
      !MobileNo ||
      !company_code ||
      !location_code ||
      !created_by ||
      !Array.isArray(calls)
    ) {
      return res.status(400).json({
        success: false,
        message: "Required fields are missing",
      });
    }

    if (calls.length > callerTrackerConfig.maxBatchSize) {
      return res.status(400).json({
        success: false,
        message: `Maximum ${callerTrackerConfig.maxBatchSize} calls are allowed per request`,
      });
    }

    const registeredMobile = normalizeMobile(MobileNo);
    if (!callerTrackerConfig.mobileRegex.test(registeredMobile)) {
      return res.status(400).json({
        success: false,
        message: "Invalid device MobileNo",
      });
    }

    const validatedCalls = [];
    const rejectedCalls = [];

    for (const call of calls) {
      const missedCallNo = normalizeMobile(call?.MissedCallNo);
      const missedCallDate = new Date(call?.MissedCallDate);

      if (!callerTrackerConfig.mobileRegex.test(missedCallNo)) {
        rejectedCalls.push({
          number: call?.MissedCallNo ?? null,
          reason: "Invalid mobile number / landline / customer-care number",
        });
        continue;
      }

      if (Number.isNaN(missedCallDate.getTime())) {
        rejectedCalls.push({
          number: call?.MissedCallNo ?? null,
          reason: "Invalid missed call date",
        });
        continue;
      }

      validatedCalls.push({ missedCallNo, missedCallDate });
    }

    const pool = await connection.connectToDatabase();

    // All inserts in this API batch commit together. If one stored-procedure
    // call fails, rollback prevents a partially committed batch.
    transaction = new sql.Transaction(pool);
    await transaction.begin();

    for (const call of validatedCalls) {
      await new sql.Request(transaction)
        .input("mode", sql.VarChar(10), "I")
        .input("MobileNo", sql.NVarChar(20), registeredMobile)
        .input("MissedCallNo", sql.NVarChar(20), call.missedCallNo)
        .input("MissedCallDate", sql.DateTime, call.missedCallDate)
        .input("Status", sql.NVarChar(18), callerTrackerConfig.defaultStatus)
        .input("company_code", sql.VarChar(18), company_code)
        .input("location_code", sql.VarChar(18), location_code)
        .input("created_by", sql.VarChar(18), created_by)
        .input("created_date", sql.DateTime, null)
        .input("modified_by", sql.VarChar(18), null)
        .input("modified_date", sql.DateTime, null)
        .query(`EXEC sp_Caller_Tracker @mode, @MobileNo, @MissedCallNo, @MissedCallDate,
        @Status, @company_code, @location_code, @created_by, @created_date, @modified_by, @modified_date`);
    }

    await transaction.commit();
    transaction = null;

    return res.status(200).json({
      success: true,
      message: "Missed calls sync completed successfully",
      totalReceived: calls.length,
      insertedCount: validatedCalls.length,
      rejectedCount: rejectedCalls.length,
      rejectedCalls,
    });
  } catch (error) {
    if (transaction) {
      try {
        await transaction.rollback();
      } catch (rollbackError) {
        console.error("Caller Tracker rollback error:", rollbackError);
      }
    }

    console.error("Caller Tracker Sync Error:", error);
    return res.status(500).json({
      success: false,
      message: error.message || "Internal Server Error",
    });
  }
};

module.exports = {
  getCallerTrackerConfig,
  syncCallerTracker,
};
