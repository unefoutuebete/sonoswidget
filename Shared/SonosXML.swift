import Foundation

public enum SonosXML {
    public static func tag(_ name: String, in xml: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = "<(?:[\\w-]+:)?\(escaped)(?:\\s[^>]*)?>([\\s\\S]*?)</(?:[\\w-]+:)?\(escaped)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(xml.startIndex..., in: xml)
        guard let match = regex.firstMatch(in: xml, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: xml) else {
            return nil
        }
        let value = xml[valueRange]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : String(value)
    }

    public static func currentValue(in soap: String) -> String? {
        tag("CurrentValue", in: soap)
    }

    public static func isSOAPFault(_ xml: String) -> Bool {
        xml.contains("<s:Fault")
            || xml.contains("<SOAP-ENV:Fault")
            || xml.contains("UPnPError")
    }

    public static func boolValue(from raw: String?) -> Bool? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else {
            return nil
        }
        if ["1", "true", "on", "yes"].contains(raw) { return true }
        if ["0", "false", "off", "no"].contains(raw) { return false }
        if let number = Int(raw) { return number != 0 }
        return nil
    }

    public static func header(_ name: String, in response: String) -> String? {
        let lines = response.split(whereSeparator: \.isNewline)
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            if parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == name.lowercased() {
                return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    public static func speaker(fromDeviceDescription xml: String, ip: String) -> SonosSpeaker? {
        let udn = tag("UDN", in: xml) ?? "uuid:\(ip)"
        let roomName = tag("roomName", in: xml)
            ?? tag("displayName", in: xml)
            ?? tag("friendlyName", in: xml)
            ?? ip
        let modelName = tag("modelName", in: xml)
            ?? tag("displayName", in: xml)
            ?? "Sonos"
        let modelNumber = tag("modelNumber", in: xml) ?? ""
        return SonosSpeaker(
            ip: ip,
            udn: udn,
            roomName: roomName,
            modelName: modelName,
            modelNumber: modelNumber
        )
    }

    public static func soapEnvelope(action: String, body: String) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:\(action) xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
        \(body)
            </u:\(action)>
          </s:Body>
        </s:Envelope>
        """
    }
}
