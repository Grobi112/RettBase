function Header() {
  return (
    <header style={{background:"#3490dc", color:"#fff", padding:"1rem"}}>
      <h1>Meine Website</h1>
      <nav>
        <a href="#" style={{marginRight:"1rem", color:"#fff"}}>Home</a>
        <a href="#" style={{color:"#fff"}}>About</a>
      </nav>
    </header>
  );
}

function Footer() {
  return (
    <footer style={{background:"#eee", padding:"1rem", marginTop:"2rem", textAlign:"center"}}>
      © {new Date().getFullYear()} Meine Website
    </footer>
  );
}

export default function App() {
  return (
    <div>
      <Header />

      <main style={{padding:"1rem"}}>
        <h2>Willkommen!</h2>
        <p>Das ist der Inhalt deiner Seite.</p>
      </main>

      <Footer />
    </div>
  );
}