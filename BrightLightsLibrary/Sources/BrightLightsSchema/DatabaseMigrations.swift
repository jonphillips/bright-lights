import SQLiteData

public enum BrightLightsDatabaseMigrations {
  public static func makeMigrator() -> DatabaseMigrator {
    var migrator = DatabaseMigrator()
    migrator.registerMigration("Create Bright Lights shared schema v1") { db in
      try db.execute(sql: """
        CREATE TABLE "households" (
          "id" TEXT PRIMARY KEY NOT NULL, "name" TEXT NOT NULL, "createdAt" TEXT NOT NULL
        ) STRICT;
        CREATE TABLE "sources" (
          "id" TEXT PRIMARY KEY NOT NULL,
          "householdID" TEXT NOT NULL REFERENCES "households"("id") ON DELETE CASCADE,
          "registryID" TEXT NOT NULL, "name" TEXT NOT NULL, "type" TEXT NOT NULL,
          "priority" TEXT NOT NULL, "area" TEXT NOT NULL, "mode" TEXT NOT NULL,
          "method" TEXT NOT NULL, "adapter" TEXT, "adapterVenue" TEXT,
          "listingURL" TEXT NOT NULL, "registeredHosts" TEXT NOT NULL,
          "excludedHosts" TEXT NOT NULL, "cadence" TEXT NOT NULL,
          "lastCheckedAt" TEXT, "lastCheckOutcome" TEXT NOT NULL,
          "lastListingCount" INTEGER, "consecutiveFailures" INTEGER NOT NULL,
          "createdAt" TEXT NOT NULL
        ) STRICT;
        CREATE TABLE "listings" (
          "id" TEXT PRIMARY KEY NOT NULL,
          "sourceID" TEXT NOT NULL REFERENCES "sources"("id") ON DELETE CASCADE,
          "stableKey" TEXT NOT NULL, "title" TEXT NOT NULL, "performers" TEXT NOT NULL,
          "room" TEXT, "ticketURL" TEXT, "onSaleAt" TEXT, "startsAt" TEXT NOT NULL,
          "closesAt" TEXT, "status" TEXT NOT NULL, "rung" TEXT NOT NULL,
          "capturedBy" TEXT NOT NULL, "firstSeenAt" TEXT NOT NULL, "updatedAt" TEXT NOT NULL
        ) STRICT;
        CREATE TABLE "stays" (
          "id" TEXT PRIMARY KEY NOT NULL,
          "householdID" TEXT NOT NULL REFERENCES "households"("id") ON DELETE CASCADE,
          "arrivesOn" TEXT NOT NULL, "departureKind" TEXT NOT NULL, "departsOn" TEXT
        ) STRICT;
        CREATE TABLE "reactions" (
          "id" TEXT PRIMARY KEY NOT NULL,
          "listingID" TEXT NOT NULL REFERENCES "listings"("id") ON DELETE CASCADE,
          "kind" TEXT NOT NULL, "note" TEXT, "authorID" TEXT, "updatedAt" TEXT NOT NULL
        ) STRICT;
        CREATE INDEX "index_sources_on_householdID" ON "sources"("householdID");
        CREATE INDEX "index_listings_on_sourceID" ON "listings"("sourceID");
        CREATE INDEX "index_stays_on_householdID" ON "stays"("householdID");
        CREATE INDEX "index_reactions_on_listingID" ON "reactions"("listingID");
        """)
    }
    return migrator
  }
}
