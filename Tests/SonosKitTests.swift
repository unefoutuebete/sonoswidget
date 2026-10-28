import XCTest
@testable import SonosArc

final class SonosKitTests: XCTestCase {
    func testParsesGetEQCurrentValue() {
        let soap = """
        <s:Envelope>
          <s:Body>
            <u:GetEQResponse>
              <CurrentValue>1</CurrentValue>
            </u:GetEQResponse>
          </s:Body>
        </s:Envelope>
        """
        XCTAssertEqual(SonosXML.currentValue(in: soap), "1")
        XCTAssertEqual(SonosXML.boolValue(from: "1"), true)
        XCTAssertEqual(SonosXML.boolValue(from: "0"), false)
        let namespaced = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:GetEQResponse xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
              <u:CurrentValue>0</u:CurrentValue>
            </u:GetEQResponse>
          </s:Body>
        </s:Envelope>
        """
        XCTAssertEqual(SonosXML.currentValue(in: namespaced), "0")
        XCTAssertFalse(SonosXML.isSOAPFault(namespaced))
    }

    func testParsesDeviceDescription() {
        let xml = """
        <root>
          <device>
            <friendlyName>192.168.1.50 - Sonos Arc</friendlyName>
            <modelName>Sonos Arc</modelName>
            <modelNumber>S19</modelNumber>
            <UDN>uuid:RINCON_ABC01400</UDN>
            <roomName>Living Room</roomName>
          </device>
        </root>
        """
        let speaker = SonosXML.speaker(fromDeviceDescription: xml, ip: "192.168.1.50")
        XCTAssertEqual(speaker?.roomName, "Living Room")
        XCTAssertEqual(speaker?.modelName, "Sonos Arc")
        XCTAssertEqual(speaker?.udn, "uuid:RINCON_ABC01400")
        XCTAssertTrue(speaker?.looksLikeSoundbar == true)
    }

    func testOnlyArcAndBeamCountAsSoundbars() {
        let arc = SonosSpeaker(ip: "1.1.1.1", udn: "a", roomName: "TV", modelName: "Sonos Arc", modelNumber: "S19")
        let beam = SonosSpeaker(ip: "1.1.1.2", udn: "b", roomName: "TV", modelName: "Sonos Beam", modelNumber: "S17")
        let one = SonosSpeaker(ip: "1.1.1.3", udn: "c", roomName: "Kitchen", modelName: "Sonos One", modelNumber: "S18")
        let lamp = SonosSpeaker(ip: "1.1.1.4", udn: "d", roomName: "Floor lamp", modelName: "SYMFONISK", modelNumber: "")
        let tableLamp = SonosSpeaker(ip: "1.1.1.5", udn: "e", roomName: "Table lamp", modelName: "SYMFONISK", modelNumber: "")
        XCTAssertTrue(arc.looksLikeSoundbar)
        XCTAssertTrue(beam.looksLikeSoundbar)
        XCTAssertFalse(one.looksLikeSoundbar)
        XCTAssertFalse(lamp.looksLikeSoundbar)
        XCTAssertFalse(tableLamp.looksLikeSoundbar)
    }

    func testParsesSSDPLocationHeader() {
        let response = """
        HTTP/1.1 200 OK
        CACHE-CONTROL: max-age = 1800
        LOCATION: http://192.168.1.50:1400/xml/device_description.xml
        ST: urn:schemas-upnp-org:device:ZonePlayer:1
        """
        XCTAssertEqual(
            SonosXML.header("LOCATION", in: response),
            "http://192.168.1.50:1400/xml/device_description.xml"
        )
    }

    func testSOAPEnvelopeIncludesEQType() {
        let envelope = SonosXML.soapEnvelope(
            action: "SetEQ",
            body: "<EQType>NightMode</EQType><DesiredValue>1</DesiredValue>"
        )
        XCTAssertTrue(envelope.contains("NightMode"))
        XCTAssertTrue(envelope.contains("SetEQ"))
        XCTAssertTrue(envelope.contains("RenderingControl:1"))
    }
}
