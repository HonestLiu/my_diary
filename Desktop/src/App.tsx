import { HashRouter, Routes, Route } from "react-router-dom";
import { lazy } from "react";
import { AppLayout } from "@/components/layout/AppLayout";

// Route-level code splitting: each page (and its heavy deps, e.g. TipTap that
// only the Editor needs) is loaded on demand instead of bloating the initial
// index chunk. See AppLayout for the shared <Suspense> boundary.
const Dashboard = lazy(() => import("@/pages/Dashboard"));
const Editor = lazy(() => import("@/pages/Editor"));
const Calendar = lazy(() => import("@/pages/Calendar"));
const Media = lazy(() => import("@/pages/Media"));
const MapPage = lazy(() => import("@/pages/Map"));
const Search = lazy(() => import("@/pages/Search"));
const Settings = lazy(() => import("@/pages/Settings"));
const OnThisDay = lazy(() => import("@/pages/OnThisDay"));

export default function App() {
  return (
    <HashRouter>
      <Routes>
        <Route element={<AppLayout />}>
          <Route index element={<Dashboard />} />
          <Route path="editor" element={<Editor />} />
          <Route path="calendar" element={<Calendar />} />
          <Route path="media" element={<Media />} />
          <Route path="map" element={<MapPage />} />
          <Route path="search" element={<Search />} />
          <Route path="settings" element={<Settings />} />
          <Route path="on-this-day" element={<OnThisDay />} />
          <Route path="*" element={<Dashboard />} />
        </Route>
      </Routes>
    </HashRouter>
  );
}
