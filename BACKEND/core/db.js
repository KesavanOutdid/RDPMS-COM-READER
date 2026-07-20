const { MongoClient, ObjectId } = require('mongodb');
const crypto = require('crypto');

const MONGODB_URI = 'mongodb+srv://outdid:outdid@cluster0.t16a63a.mongodb.net/';
const MONGODB_DB_NAME = 'RDBMS';
const COLLECTION_NAME = 'tests';

let client = null;
let db = null;
let collection = null;
let connectPromise = null;

/**
 * Connect to MongoDB Atlas (or reuse existing active connection).
 * Handles auto-reconnection and prevents duplicate concurrent connection attempts.
 */
async function connect() {
  // If already connected and active, return cached db & collection
  if (client && client.topology && client.topology.isConnected()) {
    return { db, collection };
  }

  // Avoid race conditions if connect() is called concurrently
  if (connectPromise) {
    return connectPromise;
  }

  connectPromise = (async () => {
    try {
      // Safely close stale client if present
      if (client) {
        try {
          await client.close();
        } catch (_) {}
        client = null;
      }

      client = new MongoClient(MONGODB_URI, {
        maxPoolSize: 10,
        serverSelectionTimeoutMS: 10000,
        socketTimeoutMS: 45000,
      });

      await client.connect();
      db = client.db(MONGODB_DB_NAME);
      collection = db.collection(COLLECTION_NAME);

      console.log(`🚀 Connected to MongoDB Atlas: database "${MONGODB_DB_NAME}", collection "${COLLECTION_NAME}"`);

      // Create indexes for high performance (handling 100k+ records without lag)
      await collection.createIndex({ serialNumber: 1, timestamp: -1 });
      await collection.createIndex({ timestamp: -1, _id: -1 });
      console.log('✅ Database indexes verified/created.');

      return { db, collection };
    } catch (err) {
      console.error('❌ Failed to connect to MongoDB:', err.message);
      client = null;
      db = null;
      collection = null;
      throw err;
    } finally {
      connectPromise = null;
    }
  })();

  return connectPromise;
}

/**
 * Ensures active DB connection and returns collection.
 * Auto-reconnects if the MongoDB connection was dropped.
 */
async function getCollection() {
  if (!collection || !client || !client.topology || !client.topology.isConnected()) {
    await connect();
  }
  return collection;
}

// Helper to base64 encode pagination cursor
function encodeCursor(timestamp, id) {
  return Buffer.from(`${new Date(timestamp).getTime()}_${id}`).toString('base64');
}

// Helper to decode pagination cursor
function decodeCursor(cursorStr) {
  try {
    const decoded = Buffer.from(cursorStr, 'base64').toString('utf8');
    const parts = decoded.split('_');
    if (parts.length !== 2) return null;
    return {
      timestampMs: parseInt(parts[0], 10),
      id: parts[1]
    };
  } catch (e) {
    return null;
  }
}

module.exports = {
  connect,
  
  saveTest: async (record) => {
    const col = await getCollection();
    const serialNumber = (record.serialNumber || 'UNKNOWN').trim();

    // Delete existing entry for this serial number if it exists (one entry per serial number)
    if (serialNumber !== 'UNKNOWN') {
      await col.deleteMany({ serialNumber });
    }

    const doc = {
      id: record.id || crypto.randomUUID(),
      serialNumber,
      boardType: (record.boardType || 'unknown').trim(),
      paramType: record.paramType === 'current' ? 'current' : 'voltage',
      result: record.result === 'fail' ? 'fail' : (record.result === 'FAIL' ? 'fail' : 'success'),
      testRows: Array.isArray(record.testRows) ? record.testRows : [],
      timestamp: record.timestamp ? new Date(record.timestamp) : new Date()
    };
    const result = await col.insertOne(doc);
    return { ...doc, _id: result.insertedId };
  },

  getTests: async (filters = {}) => {
    const col = await getCollection();
    const limit = Math.min(parseInt(filters.limit, 10) || 20, 100);
    const cursor = filters.cursor;

    const query = {};

    // Filter by serialNumber
    if (filters.serialNumber && filters.serialNumber !== 'All') {
      query.serialNumber = filters.serialNumber.trim();
    }

    // Filter by date range
    let dateFilter = {};
    if (filters.startDate) {
      dateFilter.$gte = new Date(filters.startDate);
    }
    if (filters.endDate) {
      // Set end date to 23:59:59.999 to cover full day
      const end = new Date(filters.endDate);
      end.setHours(23, 59, 59, 999);
      dateFilter.$lte = end;
    }
    if (Object.keys(dateFilter).length > 0) {
      query.timestamp = dateFilter;
    }

    // Handle cursor-based pagination
    if (cursor) {
      const decoded = decodeCursor(cursor);
      if (decoded) {
        const cursorTime = new Date(decoded.timestampMs);
        const cursorId = new ObjectId(decoded.id);

        if (query.timestamp) {
          const andConditions = [];
          andConditions.push({ timestamp: query.timestamp });
          delete query.timestamp;
          
          andConditions.push({
            $or: [
              { timestamp: { $lt: cursorTime } },
              { timestamp: cursorTime, _id: { $lt: cursorId } }
            ]
          });
          query.$and = andConditions;
        } else {
          query.$or = [
            { timestamp: { $lt: cursorTime } },
            { timestamp: cursorTime, _id: { $lt: cursorId } }
          ];
        }
      }
    }

    // Fetch records
    const records = await col
      .find(query)
      .sort({ timestamp: -1, _id: -1 })
      .limit(limit)
      .toArray();

    let nextCursor = null;
    if (records.length === limit) {
      const lastRec = records[records.length - 1];
      nextCursor = encodeCursor(lastRec.timestamp, lastRec._id.toString());
    }

    return {
      records,
      nextCursor
    };
  },

  getUniqueSerialNumbers: async () => {
    const col = await getCollection();
    const sns = await col.distinct('serialNumber');
    return sns.filter(Boolean).sort();
  }
};
