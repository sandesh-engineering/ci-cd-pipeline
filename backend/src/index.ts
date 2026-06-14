import "dotenv/config";
import express from "express";

const app = express();

app.get("/health", (req, res) => {
  return res
    .status(200)
    .json({ message: "Server is healthy and receiving requests!" });
});

app.listen(process.env.PORT, () => {
  console.log(`Server is running in port ${process.env.PORT}`);
});
