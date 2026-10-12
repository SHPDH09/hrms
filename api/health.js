const { Pool } = require("pg");

let pool;
function getPool() {
  if (!process.env.DATABASE_URL) return null;
  if (!pool) {
    pool = new Pool({
      connectionString: process.env.DATABASE_URL,
      ssl: process.env.PGSSLMODE === "disable" ? false : { rejectUnauthorized: true },
      max: 3,
      idleTimeoutMillis: 10000,
      connectionTimeoutMillis: 3000,
    });
  }
  return pool;
}

module.exports = async function handler(req, res) {
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("X-Content-Type-Options", "nosniff");
  if (req.method !== "GET") {
    res.setHeader("Allow", "GET");
    return res.status(405).json({ status: "method_not_allowed" });
  }
  const db = getPool();
  if (!db) return res.status(503).json({ status: "not_configured", database: "missing DATABASE_URL" });
  try {
    await db.query("SELECT 1");
    return res.status(200).json({ status: "ok", database: "connected" });
  } catch (_) {
    // Do not return database errors or connection secrets to clients.
    return res.status(503).json({ status: "unavailable", database: "connection_failed" });
  }
};
