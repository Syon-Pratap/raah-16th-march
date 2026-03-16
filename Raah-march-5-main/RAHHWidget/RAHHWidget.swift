//
//  RAHHWidget.swift
//  RAHHWidget
//
//  Created by Aakarsh Asawa on 04/03/26.
//

import WidgetKit
import SwiftUI

struct RAHHWidgetEntry: TimelineEntry {
    let date: Date
}

struct RAHHWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> RAHHWidgetEntry {
        RAHHWidgetEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (RAHHWidgetEntry) -> Void) {
        completion(RAHHWidgetEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RAHHWidgetEntry>) -> Void) {
        completion(Timeline(entries: [RAHHWidgetEntry(date: Date())], policy: .never))
    }
}

struct RAHHWidgetEntryView: View {
    var entry: RAHHWidgetEntry

    var body: some View {
        ZStack {
            // Outer glow ring
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.orange.opacity(0.5), Color.clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 24
                    )
                )
                .scaleEffect(1.4)

            // Orb body
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.78, blue: 0.2),
                            Color(red: 1.0, green: 0.45, blue: 0.0),
                            Color(red: 0.65, green: 0.18, blue: 0.0),
                        ],
                        center: UnitPoint(x: 0.35, y: 0.3),
                        startRadius: 1,
                        endRadius: 20
                    )
                )

            // Specular highlight
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.75), Color.clear],
                        center: UnitPoint(x: 0.35, y: 0.3),
                        startRadius: 0,
                        endRadius: 8
                    )
                )
                .scaleEffect(0.42)
                .offset(x: -5, y: -5)
        }
        .widgetURL(URL(string: "raah://start"))
    }
}

struct RAHHWidget: Widget {
    let kind: String = "com.aakarsh.RAAH.lockscreen"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RAHHWidgetProvider()) { entry in
            RAHHWidgetEntryView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("RAAH")
        .description("Tap to start a voice conversation")
        .supportedFamilies([.accessoryCircular])
    }
}
