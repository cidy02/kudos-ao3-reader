import Testing
@testable import Kudos

struct SubjectScreenRoleTests {
    @Test func onlyTheSubjectRoleUsesAnIdentityWash() {
        #expect(!SubjectScreenRole.content.usesSubjectWash)
        #expect(!SubjectScreenRole.grouped.usesSubjectWash)
        #expect(SubjectScreenRole.subjectWash.usesSubjectWash)
    }

    @Test func rolesMapToTheCorrectBaseSurface() {
        #expect(SubjectScreenRole.content.baseSurface == .content)
        #expect(SubjectScreenRole.grouped.baseSurface == .grouped)
        #expect(SubjectScreenRole.subjectWash.baseSurface == .content)
    }

    @Test func washGeometryMatchesTheSharedRule() {
        #expect(SubjectWashGeometry.height == 380)
        #expect(SubjectWashGeometry.opacities == [0.20, 0.12, 0.05, 0])
        #expect(SubjectWashGeometry.locations == [0, 0.5, 0.75, 1])
    }
}
