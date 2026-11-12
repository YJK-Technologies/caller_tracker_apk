//server.js
const express = require("express");
const cors = require("cors");
const dataRoutes = require("./routes/dataRoutes");
const app = express();
const PORT = 5547;

app.use(cors());
app.use(express.json({limit:'50mb'}));
app.use(express.urlencoded({ limit: "50mb", extended: true }));

app.use("/", dataRoutes);

app.listen(PORT, "0.0.0.0", () => {
  console.log(`Server running on port ${PORT}`);
});
