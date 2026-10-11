import SwiftUI

// The controls themselves are the editor's (`AdjustControl`); the lab only adds a fake value store.
typealias LabAdjustGroup = AdjustGroup
typealias LabAdjustParam = AdjustControl

struct LabAdjustValues: Equatable {
    private var storage: [LabAdjustParam: Double] = [:]

    subscript(_ param: LabAdjustParam) -> Double {
        get { storage[param] ?? param.neutral }
        set { storage[param] = newValue }
    }

    func isChanged(_ param: LabAdjustParam) -> Bool { abs(self[param] - param.neutral) > 0.0001 }
    func changedCount(in group: LabAdjustGroup) -> Int { LabAdjustParam.allCases.filter { $0.group == group && isChanged($0) }.count }
}
