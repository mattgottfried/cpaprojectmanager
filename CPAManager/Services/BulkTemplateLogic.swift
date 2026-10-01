import Foundation

// Pure rules for adding a template's tasks to many jobs at once. A job that already has an open
// task with the same title (any case) doesn't get a second copy, so running it twice, or over
// jobs that were started from the template, never duplicates work. Unit-tested.

enum BulkTemplate {
    /// Lower-cased titles of the job's open tasks: what to skip when applying a template.
    static func skipSet(openTaskTitles: [String]) -> Set<String> {
        Set(openTaskTitles.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty })
    }

    /// Positions of the template steps a job would actually receive.
    static func newStepIndices(templateTitles: [String], openTaskTitles: [String]) -> [Int] {
        let skip = skipSet(openTaskTitles: openTaskTitles)
        return templateTitles.indices.filter { !skip.contains(templateTitles[$0].trimmingCharacters(in: .whitespaces).lowercased()) }
    }

    static func summary(jobs: Int, tasks: Int, skippedJobs: Int) -> String {
        var text = tasks == 0 ? "No new tasks added" : "Added \(tasks) task\(tasks == 1 ? "" : "s") to \(jobs) job\(jobs == 1 ? "" : "s")"
        if skippedJobs > 0 {
            text += tasks == 0 ? " — every job already has them" : " (\(skippedJobs) already had them)"
        }
        return text
    }
}
