//
//  RAHHWidgetLiveActivity.swift
//  RAHHWidget
//
//  Created by Aakarsh Asawa on 04/03/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct RAHHWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct RAHHWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RAHHWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension RAHHWidgetAttributes {
    fileprivate static var preview: RAHHWidgetAttributes {
        RAHHWidgetAttributes(name: "World")
    }
}

extension RAHHWidgetAttributes.ContentState {
    fileprivate static var smiley: RAHHWidgetAttributes.ContentState {
        RAHHWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: RAHHWidgetAttributes.ContentState {
         RAHHWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: RAHHWidgetAttributes.preview) {
   RAHHWidgetLiveActivity()
} contentStates: {
    RAHHWidgetAttributes.ContentState.smiley
    RAHHWidgetAttributes.ContentState.starEyes
}
