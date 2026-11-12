//connection/connection.js
const sql = require("mssql");
const dbConfig = require("../config/dbConfig");

const connectToDatabase = async () => {
  try {
    return await sql.connect(dbConfig);
   
  } catch (error) {
    console.error("Error connecting to the database:", error);
    throw error;
  }
};

const closeDatabaseConnection = () => {
  sql.close();
};

module.exports = {
  connectToDatabase,
  closeDatabaseConnection,
};
