import Foundation
import CoreData

protocol LibraryStore: AnyObject {
    func allBooks() -> [BookRecord]
    func book(id: UUID) -> BookRecord?
    func add(_ record: BookRecord) throws
    func remove(id: UUID) throws
    func updateLocation(id: UUID, location: ReadingLocation) throws
    func updateLastOpened(id: UUID, at date: Date) throws
    func updateProgress(id: UUID, progress: Double) throws
    func updateBookmarks(id: UUID, bookmarksJSON: String) throws
}

final class UnavailableLibraryStore: LibraryStore {
    func allBooks() -> [BookRecord] { [] }
    func book(id: UUID) -> BookRecord? { nil }
    func add(_ record: BookRecord) throws { throw ImportFailure.io }
    func remove(id: UUID) throws { throw ImportFailure.io }
    func updateLocation(id: UUID, location: ReadingLocation) throws { throw ImportFailure.io }
    func updateLastOpened(id: UUID, at date: Date) throws { throw ImportFailure.io }
    func updateProgress(id: UUID, progress: Double) throws { throw ImportFailure.io }
    func updateBookmarks(id: UUID, bookmarksJSON: String) throws { throw ImportFailure.io }
}

final class PersistentLibraryStore: LibraryStore {
    private let context: NSManagedObjectContext
    init(inMemory: Bool = false, fileManager: FileManager = .default) throws {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: Self.makeModel())
        if inMemory { try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil, options: nil) }
        else {
            let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let directory = support.appendingPathComponent("BookReader", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: directory.appendingPathComponent("Library.sqlite"), options: [NSMigratePersistentStoresAutomaticallyOption: true, NSInferMappingModelAutomaticallyOption: true])
        }
        context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func allBooks() -> [BookRecord] {
        var records: [BookRecord] = []
        context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "BookRecordEntity")
            request.sortDescriptors = [NSSortDescriptor(key: "lastOpenedAt", ascending: false), NSSortDescriptor(key: "title", ascending: true)]
            if let objects = try? context.fetch(request) { records = objects.compactMap(Self.decode) }
        }
        return records
    }
    func book(id: UUID) -> BookRecord? {
        var record: BookRecord?
        context.performAndWait { record = (try? Self.fetch(context, id: id)).flatMap { $0 }.flatMap(Self.decode) }
        return record
    }
    func add(_ record: BookRecord) throws {
        try context.performAndWaitThrowing {
            if try Self.fetch(context, id: record.id) != nil { throw ImportFailure.invalid }
            let request = NSFetchRequest<NSManagedObject>(entityName: "BookRecordEntity")
            request.predicate = NSPredicate(format: "sha256 == %@", record.sha256)
            if let existing = try context.fetch(request).first, let id = existing.value(forKey: "id") as? UUID { throw ImportFailure.duplicate(existingID: id) }
            let object = NSEntityDescription.insertNewObject(forEntityName: "BookRecordEntity", into: context)
            Self.encode(record, into: object)
            do { try context.save() } catch { context.delete(object); throw ImportFailure.io }
        }
    }
    func remove(id: UUID) throws {
        try context.performAndWaitThrowing {
            guard let object = try Self.fetch(context, id: id) else { return }
            context.delete(object)
            do { try context.save() } catch { context.rollback(); throw ImportFailure.io }
        }
    }
    func updateLocation(id: UUID, location: ReadingLocation) throws {
        try update(id: id) { object in
            object.setValue(String(decoding: try JSONEncoder().encode(location), as: UTF8.self), forKey: "locatorJSON")
            if case let .pdf(page, _, _) = location.position { object.setValue(Double(max(page, 0)), forKey: "progress") }
        }
    }
    func updateLastOpened(id: UUID, at date: Date = Date()) throws { try update(id: id) { $0.setValue(date, forKey: "lastOpenedAt") } }
    func updateProgress(id: UUID, progress: Double) throws { try update(id: id) { $0.setValue(progress.isFinite ? min(max(progress, 0), 1) : 0, forKey: "progress") } }
    func updateBookmarks(id: UUID, bookmarksJSON: String) throws { try update(id: id) { $0.setValue(bookmarksJSON, forKey: "bookmarkJSON") } }

    private func update(id: UUID, mutation: (NSManagedObject) throws -> Void) throws {
        try context.performAndWaitThrowing {
            guard let object = try Self.fetch(context, id: id) else { throw ImportFailure.invalid }
            try mutation(object)
            do { try context.save() } catch { context.rollback(); throw ImportFailure.io }
        }
    }
    private static func fetch(_ context: NSManagedObjectContext, id: UUID) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "BookRecordEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try context.fetch(request).first
    }
    private static func decode(_ object: NSManagedObject) -> BookRecord? {
        guard let id = object.value(forKey: "id") as? UUID,
              let path = object.value(forKey: "relativePath") as? String,
              let formatName = object.value(forKey: "format") as? String,
              let format = BookFormat(rawValue: formatName),
              let title = object.value(forKey: "title") as? String,
              let hash = object.value(forKey: "sha256") as? String,
              let added = object.value(forKey: "addedAt") as? Date else { return nil }
        return BookRecord(id: id, relativePath: path, format: format, title: title,
                          author: object.value(forKey: "author") as? String,
                          fileSize: object.value(forKey: "fileSize") as? Int64 ?? 0, sha256: hash,
                          addedAt: added, lastOpenedAt: object.value(forKey: "lastOpenedAt") as? Date,
                          progress: object.value(forKey: "progress") as? Double ?? 0,
                          locatorJSON: object.value(forKey: "locatorJSON") as? String,
                          bookmarkJSON: object.value(forKey: "bookmarkJSON") as? String,
                          coverPath: object.value(forKey: "coverPath") as? String)
    }
    private static func encode(_ record: BookRecord, into object: NSManagedObject) {
        object.setValue(record.id, forKey: "id")
        object.setValue(record.relativePath, forKey: "relativePath")
        object.setValue(record.format.rawValue, forKey: "format")
        object.setValue(record.title, forKey: "title")
        object.setValue(record.author, forKey: "author")
        object.setValue(record.fileSize, forKey: "fileSize")
        object.setValue(record.sha256, forKey: "sha256")
        object.setValue(record.addedAt, forKey: "addedAt")
        object.setValue(record.lastOpenedAt, forKey: "lastOpenedAt")
        object.setValue(record.progress, forKey: "progress")
        object.setValue(record.locatorJSON, forKey: "locatorJSON")
        object.setValue(record.bookmarkJSON, forKey: "bookmarkJSON")
        object.setValue(record.coverPath, forKey: "coverPath")
    }
    private static func makeModel() -> NSManagedObjectModel {
        let entity = NSEntityDescription()
        entity.name = "BookRecordEntity"
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.uniquenessConstraints = [["id"], ["sha256"]]
        entity.properties = [
            attribute("id", .UUIDAttributeType, optional: false), attribute("relativePath", .stringAttributeType, optional: false),
            attribute("format", .stringAttributeType, optional: false), attribute("title", .stringAttributeType, optional: false),
            attribute("author", .stringAttributeType), attribute("fileSize", .integer64AttributeType, optional: false, defaultValue: 0),
            attribute("sha256", .stringAttributeType, optional: false), attribute("addedAt", .dateAttributeType, optional: false),
            attribute("lastOpenedAt", .dateAttributeType), attribute("progress", .doubleAttributeType, optional: false, defaultValue: 0),
            attribute("locatorJSON", .stringAttributeType), attribute("bookmarkJSON", .stringAttributeType), attribute("coverPath", .stringAttributeType)
        ]
        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }
    private static func attribute(_ name: String, _ type: NSAttributeType, optional: Bool = true, defaultValue: Any? = nil) -> NSAttributeDescription {
        let property = NSAttributeDescription()
        property.name = name
        property.attributeType = type
        property.isOptional = optional
        property.defaultValue = defaultValue
        return property
    }
}

private extension NSManagedObjectContext {
    func performAndWaitThrowing(_ block: () throws -> Void) throws {
        var result: Result<Void, Error>!
        performAndWait { result = Result { try block() } }
        try result.get()
    }
}
